defmodule ElibSQL.Protobuf do
  @moduledoc """
  Protobuf encoder and decoder for Hrana.
  """
  defstruct [:messages]

  @type t :: %__MODULE__{
          messages: %{binary() => message()}
        }

  @typedoc "A valid protobuf field number. Note that different messages may have other reserved numbers within this types ranges"
  @type field_number() :: 1..18999 | 20000..536_870_911

  @typedoc "Valid cardinalities for a protobuf field"
  @type cardinality() :: :optional | :repeated | :map | :oneof

  @typedoc "List of valid proto types (besides other message names)"
  @type proto_type() ::
          :double
          | :float
          | :int32
          | :int64
          | :uint32
          | :uint64
          | :sint32
          | :sint64
          | :fixed32
          | :fixed64
          | :sfixed32
          | :sfixed64
          | :bool
          | :string
          | :bytes

  @type proto_integer_or_string() ::
          :double
          | :int32
          | :int64
          | :uint32
          | :uint64
          | :sint32
          | :sint64
          | :fixed32
          | :fixed64
          | :sfixed32
          | :sfixed64
          | :bool
          | :string

  @typedoc "Struct for a message field"
  @type message_field() :: %{
          cardinality: cardinality(),
          name: binary(),
          field_number: field_number(),
          type: proto_type() | binary() | {proto_integer_or_string(), proto_type() | binary()},
          oneof_group: binary() | nil
        }

  @typedoc "Arbitrary message"
  @type message() :: %{
          name: binary(),
          fields: %{field_number() => message_field()},
          oneof_groups: %{binary() => MapSet.t(field_number())},
          reserved_numbers: MapSet.t(field_number()),
          reserved_names: MapSet.t(binary()),
          messages: %{binary() => message()}
        }

  @typedoc "Reserved words in proto"
  @type reserved_word() :: :syntax | :message | :reserved | :package

  @typedoc "Reserved symbols in proto"
  @type reserved_symbol() ::
          :semi_colon
          | :open_brace
          | :close_brace
          | :equals
          | :quote
          | :comma
          | :open_angle
          | :close_angle

  @typedoc "Different types of tokens in a proto file"
  @type token() ::
          proto_type()
          | binary()
          | reserved_word()
          | reserved_symbol()
          | cardinality()
          | field_number()

  defguardp is_whitespace(char) when char in ["\t", "\r", "\n", " "]

  defguardp is_reserved_symbol(char) when char in [";", "{", "}", "=", "\"", "<", ">"]

  defguardp is_field_number(token) when token in 1..18999 or token in 20000..536_870_911

  # note that :oneof is not included in this since its syntax is different
  defguardp is_cardinality(token) when token in [:optional, :repeated, :map]

  defguardp is_proto_type(token)
            when token in [
                   :double,
                   :float,
                   :int32,
                   :int64,
                   :uint32,
                   :uint64,
                   :sint32,
                   :sint64,
                   :fixed32,
                   :fixed64,
                   :sfixed32,
                   :sfixed64,
                   :bool,
                   :string,
                   :bytes
                 ] or Kernel.is_binary(token)

  defguardp is_map_key(token)
            when token in [
                   :double,
                   :int32,
                   :int64,
                   :uint32,
                   :uint64,
                   :sint32,
                   :sint64,
                   :fixed32,
                   :fixed64,
                   :sfixed32,
                   :sfixed64,
                   :bool,
                   :string
                 ]

  defguardp is_reserved_word(token) when token in [:syntax, :message, :reserved, :package]

  defguardp is_identifier(token)
            when is_proto_type(token) or is_reserved_word(token) or
                   Kernel.binary_part(token, 0, 1) in [
                     "a",
                     "b",
                     "c",
                     "d",
                     "e",
                     "f",
                     "g",
                     "h",
                     "i",
                     "j",
                     "k",
                     "l",
                     "m",
                     "n",
                     "o",
                     "p",
                     "q",
                     "r",
                     "s",
                     "t",
                     "u",
                     "v",
                     "w",
                     "x",
                     "y",
                     "z",
                     "A",
                     "B",
                     "C",
                     "D",
                     "E",
                     "F",
                     "G",
                     "H",
                     "I",
                     "J",
                     "K",
                     "L",
                     "M",
                     "N",
                     "O",
                     "P",
                     "Q",
                     "R",
                     "S",
                     "T",
                     "U",
                     "V",
                     "W",
                     "X",
                     "Y",
                     "Z"
                   ]

  @doc """
  Parse in a file at a path into a protobuf struct (`__MODULE__%{}`)
  """
  @spec parse_file(binary()) :: {:ok, t()} | {:error, any()}
  def parse_file(path) do
    with {:ok, contents} <- File.read(path),
         tokens <- tokenize(contents),
         {:proto_3, tokens} <- parse_syntax_version(tokens),
         messages <- parse_tokens(tokens),
         true <- messages_valid?(messages) do
      %__MODULE__{
        messages: messages |> Enum.reduce(%{}, fn m, acc -> Map.put(acc, m.name, m) end)
      }
    end
  end

  @spec find_definition([binary()], [%{binary() => message()}]) :: message() | nil
  def find_definition(["" | rest], scope_stack),
    do: find_definition(rest, Enum.reverse(scope_stack))

  def find_definition(_type, scope_stack) when scope_stack == [], do: nil

  def find_definition([top_identifier | rest_identifier], [top_scope | rest_scope]) do
    definition =
      Enum.reduce_while(rest_identifier, Map.get(top_scope, top_identifier), fn x, acc ->
        if acc != nil, do: {:cont, Map.get(acc.messages, x)}, else: {:halt, acc}
      end)

    if definition != nil,
      do: definition,
      else: find_definition([top_identifier | rest_identifier], rest_scope)
  end

  @doc """
  Traverses a message tree where every message is considered
  a node. It validates every submessage within the node, aka all root.messages
  """
  @spec validate_message_tree(message(), [%{binary() => message()}]) :: boolean()
  def validate_message_tree(root, scope_stack) do
    scope_stack = [root.messages | scope_stack]
    messages = Map.values(root.messages)

    with true <-
           Enum.all?(messages, fn m ->
             m.fields
             |> Map.values()
             |> Enum.map(fn f ->
               case f.type do
                 # key type can't be a message so we can ignore it, it is valid
                 # already
                 {_key_type, value_type} -> value_type
                 type -> type
               end
             end)
             |> Enum.filter(&Kernel.is_binary/1)
             |> Enum.map(fn type -> String.split(type, ".") end)
             |> Enum.all?(fn type -> find_definition(type, [m.messages | scope_stack]) != nil end)
           end) || :undefined_field,

         # make sure no oneof groups specify overlapping field numbers
         true <-
           Enum.all?(messages, fn m ->
             intersection_count =
               m.oneof_groups
               |> Map.values()
               |> Enum.reduce(MapSet.new(), fn g, acc -> MapSet.intersection(acc, g) end)
               |> MapSet.size()

             intersection_count == 0
           end) || :overlapping_oneof_field_numbers,

         # make sure that no field numbers fall into the reserved field numbers
         # specified in the message
         true <-
           Enum.all?(messages, fn m ->
             intersection_count =
               m.fields
               |> Map.keys()
               |> MapSet.new()
               |> MapSet.intersection(m.reserved_numbers)
               |> MapSet.size()

             intersection_count == 0
           end) || :using_reserved_field_number,

         # make sure that no field names fall into the reserved field names
         true <-
           Enum.all?(messages, fn m ->
             intersection_count =
               m.fields
               |> Map.values()
               |> Enum.map(fn f -> f.name end)
               |> MapSet.new()
               |> MapSet.intersection(m.reserved_names)
               |> MapSet.size()

             intersection_count == 0
           end) || :using_reserved_field_name,

         # make sure that no field names are the same within a message
         true <-
           Enum.all?(messages, fn m ->
             unique_fields =
               m.fields
               |> Map.values()
               |> Enum.map(fn f -> f.name end)
               |> MapSet.new()
               |> MapSet.size()

             total_fields = m.fields |> Map.values() |> Enum.count()
             total_fields == unique_fields
           end) || :duplicate_field_name,
         # now validate all child messages
         true <-
           Enum.all?(messages, fn m -> validate_message_tree(m, scope_stack) end) do
      true
    else
      x -> {x, false}
    end
  end

  @doc """
  Validates a set of messages to ensure all of them are valid
  """
  @spec messages_valid?([message()]) :: boolean()
  def messages_valid?(messages) do
    message_dict = messages |> Enum.reduce(%{}, fn m, acc -> Map.put(acc, m.name, m) end)

    dummy_root = %{
      name: nil,
      fields: %{},
      messages: message_dict,
      oneof_groups: %{},
      reserved_names: MapSet.new(),
      reserved_numbers: MapSet.new()
    }

    Kernel.map_size(message_dict) == Enum.count(messages) && validate_message_tree(dummy_root, [])
  end

  @doc """
  Parse in all the tokens to get the messages they define. 
  Does not allow syntax to be set again so that token must have been
  parsed out already.
  """
  @spec parse_tokens([token()]) :: [message()]
  def parse_tokens(tokens) when tokens == [], do: []

  def parse_tokens(tokens) do
    case tokens do
      [:message, message_name, :open_brace | rest] ->
        message_body = %{
          name: message_name,
          fields: %{},
          messages: %{},
          oneof_groups: %{},
          reserved_names: MapSet.new(),
          reserved_numbers: MapSet.new()
        }

        {rest, message_body} = parse_message_body(rest, message_body)
        [message_body | parse_tokens(rest)]

      [:package | _] ->
        raise "Packages aren't supported (yet)"

      [:syntax | _] ->
        raise "syntax cannot be specified more than once or after the first non-whitespace or comment line"

      _ ->
        raise "Invalid syntax found #{tokens}"
    end
  end

  @doc """
  Parse the body of a message. Must run this function after consuming 
  :message, identifier, :open_brace
  """
  @spec parse_message_body([token()], message()) :: {[token()], message()}
  def parse_message_body([:oneof, identifier, :open_brace | rest], message)
      when Kernel.is_binary(identifier) do
    if Map.has_key?(message.oneof_groups, identifier) do
      raise "oneof groups cannot share the same name. multiple defined with name #{identifier}"
    end

    # we can treat the body of the oneof scope as a nested message.
    # however, if it turns out any other keys besides :fields are populated,
    # raise an error since that information can't be set within a oneof block
    nested_message = %{
      name: nil,
      fields: %{},
      messages: %{},
      oneof_groups: %{},
      reserved_names: MapSet.new(),
      reserved_numbers: MapSet.new()
    }

    {rest, nested_message} = parse_message_body(rest, nested_message)

    cond do
      Kernel.map_size(nested_message.messages) > 0 ->
        raise "Cannot specify messages within a oneof block"

      Kernel.map_size(nested_message.oneof_groups) > 0 ->
        raise "Cannot specify nested oneof groups"

      MapSet.size(nested_message.reserved_names) > 0 ->
        raise "Cannot specify reserved names within a oneof block"

      MapSet.size(nested_message.reserved_numbers) > 0 ->
        raise "Cannot specify reserved field numbers within a oneof block"

      Map.intersect(message.fields, nested_message.fields) |> Kernel.map_size() > 0 ->
        raise "Cannot specify duplicate fields within oneof block '#{identifier}'. Fields numbers must be unique"

      true ->
        nil
    end

    fields =
      nested_message.fields
      |> Map.values()
      |> Enum.map(fn f -> Map.put(f, :oneof_group, identifier) end)
      |> Enum.reduce(%{}, fn f, acc -> Map.put(acc, f.field_number, f) end)

    message = Map.put(message, :fields, Map.merge(message.fields, fields))

    message =
      Map.put(
        message,
        :oneof_groups,
        Map.put(message.oneof_groups, identifier, Map.keys(message.fields) |> MapSet.new())
      )

    parse_message_body(rest, message)
  end

  def parse_message_body([:close_brace | rest], message), do: {rest, message}

  def parse_message_body(
        [
          :map,
          :open_angle,
          key_type,
          :comma,
          value_type,
          :close_angle,
          field_name,
          :equals,
          field_number,
          :semi_colon | rest
        ],
        message
      )
      when is_map_key(key_type) and is_proto_type(value_type) and is_identifier(field_name) and
             is_field_number(field_number) do
    field = %{
      cardinality: :map,
      name: "#{field_name}",
      field_number: field_number,
      type: {key_type, value_type},
      oneof_group: nil
    }

    message = Map.put(message, :fields, Map.put(message.fields, field_number, field))
    parse_message_body(rest, message)
  end

  def parse_message_body(
        [cardinality, data_type, field_name, :equals, field_number, :semi_colon | rest],
        message
      )
      when is_proto_type(data_type) and is_cardinality(cardinality) and is_identifier(field_name) and
             is_field_number(field_number) do
    # the name could be an atom if it is a protected word (don't ask why those are allowed)
    field = %{
      cardinality: cardinality,
      name: "#{field_name}",
      field_number: field_number,
      type: data_type,
      oneof_group: nil
    }

    if Map.has_key?(message.fields, field_number) do
      raise "Duplicate field number #{field_number} in #{message.name}"
    end

    message = Map.put(message, :fields, Map.put(message.fields, field_number, field))
    parse_message_body(rest, message)
  end

  def parse_message_body(
        [data_type, field_name, :equals, field_number, :semi_colon | rest],
        message
      )
      when is_proto_type(data_type) and is_identifier(field_name) and
             is_field_number(field_number) do
    # the name could be an atom if it is a protected word (don't ask why those are allowed)
    field = %{
      cardinality: :optional,
      name: "#{field_name}",
      field_number: field_number,
      type: data_type,
      oneof_group: nil
    }

    if Map.has_key?(message.fields, field_number) do
      raise "Duplicate field number #{field_number} in #{message.name}"
    end

    message = Map.put(message, :fields, Map.put(message.fields, field_number, field))
    parse_message_body(rest, message)
  end

  def parse_message_body([:message, message_name, :open_brace | rest], message)
      when Kernel.is_binary(message_name) do
    nested_message = %{
      name: message_name,
      fields: %{},
      messages: %{},
      oneof_groups: %{},
      reserved_names: MapSet.new(),
      reserved_numbers: MapSet.new()
    }

    {rest, nested_message} = parse_message_body(rest, nested_message)

    if Map.has_key?(message.messages, message_name) do
      raise "Duplicate nested message #{message_name} in #{message.name}"
    end

    message = Map.put(message, :messages, Map.put(message.messages, message_name, nested_message))
    parse_message_body(rest, message)
  end

  def parse_message_body([:reserved | rest], message) do
    {rest, constants} = parse_constant_list(rest)

    message =
      case constants do
        [first_item | remaining_items] when is_field_number(first_item) ->
          true = Enum.all?(remaining_items, &is_field_number/1)

          Map.put(
            message,
            :reserved_numbers,
            MapSet.union(message.reserved_numbers, MapSet.new(constants))
          )

        [first_item | remaining_items] when is_identifier(first_item) ->
          true = Enum.all?(remaining_items, &is_identifier/1)

          Map.put(
            message,
            :reserved_names,
            MapSet.union(message.reserved_numbers, MapSet.new(constants))
          )
      end

    parse_message_body(rest, message)
  end

  @spec parse_constant_list([token()]) :: {[token()], [number()] | [binary()]}
  defp parse_constant_list([:quote, constant, :quote, :semi_colon | rest]),
    do: {rest, ["#{constant}"]}

  defp parse_constant_list([:quote, constant, :quote, :comma | rest]) do
    # ensure the constant is of string type
    constant = "#{constant}"
    {rest, constants} = parse_constant_list(rest)
    {rest, [constant | constants]}
  end

  defp parse_constant_list([constant, :semi_colon | rest]) when Kernel.is_integer(constant),
    do: {rest, [constant]}

  defp parse_constant_list([constant, :comma | rest]) when Kernel.is_integer(constant) do
    {rest, constants} = parse_constant_list(rest)
    {rest, [constant | constants]}
  end

  @doc """
  Tokenize the input string into reverse order
  """
  @spec tokenize(binary()) :: [token()]
  def tokenize(<<char::binary-size(1), rest::binary>>) when is_whitespace(char),
    do: tokenize(rest)

  def tokenize(input) when input == "", do: []

  def tokenize(input) do
    case input do
      <<"//", rest::binary>> ->
        {_, rest} = read_comment("//" <> rest)
        tokenize(rest)

      <<"/*", rest::binary>> ->
        {_, rest} = read_comment("/*" <> rest)
        tokenize(rest)

      <<"package", _::binary>> ->
        raise "Package not supported"

      <<"syntax", rest::binary>> ->
        [:syntax | tokenize(rest)]

      <<"message", rest::binary>> ->
        [:message | tokenize(rest)]

      <<"oneof", rest::binary>> ->
        [:oneof | tokenize(rest)]

      <<"repeated", rest::binary>> ->
        [:repeated | tokenize(rest)]

      <<"optional", rest::binary>> ->
        [:optional | tokenize(rest)]

      <<"map", rest::binary>> ->
        [:map | tokenize(rest)]

      <<"reserved", rest::binary>> ->
        [:reserved | tokenize(rest)]

      <<"{", rest::binary>> ->
        [:open_brace | tokenize(rest)]

      <<"}", rest::binary>> ->
        [:close_brace | tokenize(rest)]

      <<";", rest::binary>> ->
        [:semi_colon | tokenize(rest)]

      <<"=", rest::binary>> ->
        [:equals | tokenize(rest)]

      <<"\"", rest::binary>> ->
        [:quote | tokenize(rest)]

      <<",", rest::binary>> ->
        [:comma | tokenize(rest)]

      <<"<", rest::binary>> ->
        [:open_angle | tokenize(rest)]

      <<">", rest::binary>> ->
        [:close_angle | tokenize(rest)]

      <<"double", rest::binary>> ->
        [:double | tokenize(rest)]

      <<"float", rest::binary>> ->
        [:float | tokenize(rest)]

      <<"int32", rest::binary>> ->
        [:int32 | tokenize(rest)]

      <<"int64", rest::binary>> ->
        [:int64 | tokenize(rest)]

      <<"uint32", rest::binary>> ->
        [:uint32 | tokenize(rest)]

      <<"uint64", rest::binary>> ->
        [:uint64 | tokenize(rest)]

      <<"sint32", rest::binary>> ->
        [:sint32 | tokenize(rest)]

      <<"sint64", rest::binary>> ->
        [:sint64 | tokenize(rest)]

      <<"fixed32", rest::binary>> ->
        [:fixed32 | tokenize(rest)]

      <<"fixed64", rest::binary>> ->
        [:fixed64 | tokenize(rest)]

      <<"sfixed32", rest::binary>> ->
        [:sfixed32 | tokenize(rest)]

      <<"sfixed64", rest::binary>> ->
        [:sfixed64 | tokenize(rest)]

      <<"bool", rest::binary>> ->
        [:bool | tokenize(rest)]

      <<"string", rest::binary>> ->
        [:string | tokenize(rest)]

      <<"bytes", rest::binary>> ->
        [:bytes | tokenize(rest)]

      _ ->
        {identifier, rest} = read_identifier(input)

        case Integer.parse(identifier) do
          :error -> [identifier | tokenize(rest)]
          {val, ""} -> [val | tokenize(rest)]
          {val, _} -> raise "Invalid identifier #{val}"
        end
    end
  end

  def read_identifier(<<char::binary-size(1), rest::binary>>)
      when is_whitespace(char) or is_reserved_symbol(char),
      do: {"", char <> rest}

  def read_identifier(input) when input == "", do: {"", ""}

  def read_identifier(<<char::binary-size(1), rest::binary>>) do
    {remaining_identifier, remaining_binary} = read_identifier(rest)
    {char <> remaining_identifier, remaining_binary}
  end

  @doc """
  Parses the tokens for the syntax version. Returns :proto_2 by
  default if the first token is not :syntax
  """
  @spec parse_syntax_version([token()]) :: {:proto_2 | :proto_3, [token()]}
  def parse_syntax_version([:syntax | rest]) do
    case rest do
      [:equals, :quote, value, :quote, :semi_colon | rest] ->
        case value do
          "proto3" -> {:proto_3, rest}
          "proto2" -> {:proto_2, rest}
          _ -> raise "Invalid version"
        end

      _ ->
        raise "Invalid syntax definition"
    end
  end

  def parse_syntax_version(input), do: {:proto_2, input}

  @doc """
  Parses the comment (including the decorators like // or /* */
  and returns the comment as well as the remaining binary
  """
  @spec read_comment(binary()) :: {binary(), binary()}
  def read_comment(<<"//", rest::binary>>) do
    case String.split(rest, ["\r", "\n"], parts: 2) do
      [comment, rest] -> {"//" <> comment, rest}
      [comment] -> {"//" <> comment, ""}
    end
  end

  def read_comment(<<"/*", rest::binary>>) do
    case String.split(rest, "*/", parts: 2) do
      [comment, rest] -> {"/*" <> comment <> "*/", rest}
      [comment] -> raise "Unterminated block comment #{comment}"
    end
  end
end
