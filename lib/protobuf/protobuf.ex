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
  @type cardinality() :: :optional | :repeated | :map

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

  @typedoc "Struct for a message field"
  @type message_field() :: %{
          cardinality: cardinality(),
          name: binary(),
          field_number: field_number(),
          type: proto_type() | binary()
        }

  @typedoc "Arbitrary message"
  @type message() :: %{
          name: binary(),
          fields: %{field_number() => message_field()},
          reserved_numbers: MapSet.t(field_number()),
          reserved_names: MapSet.t(binary())
        }

  @typedoc "Reserved words in proto"
  @type reserved_word() :: :syntax | :message | :reserved

  @typedoc "Reserved symbols in proto"
  @type reserved_symbol() :: :semi_colon | :open_brace | :close_brace | :equals | :quote

  @typedoc "Different types of tokens in a proto file"
  @type token() ::
          proto_type()
          | binary()
          | reserved_word()
          | reserved_symbol()
          | cardinality()
          | field_number()

  defguardp is_whitespace(char) when char == " " or char == "\n" or char == "\r" or char == "\t"

  defguardp is_reserved_symbol(char)
            when char == ";" or char == "{" or char == "}" or char == "=" or char == "\""

  @doc """
  Parse in a file at a path into a protobuf struct (`__MODULE__%{}`)
  """
  @spec parse_file(binary()) :: {:ok, t()} | {:error, any()}
  def parse_file(path) do
    with {:ok, contents} <- File.read(path),
         tokens <- tokenize(contents),
         {:proto_3, tokens} <- parse_syntax_version(tokens),
         {:ok, messages} <- parse_messages(tokens) do
      %__MODULE__{messages: messages}
    end
  end

  @doc """
  Parse in all the tokens to get the messages they define
  """
  @spec parse_messages([token()]) :: {:ok, [message()]}
  defp parse_messages(tokens) do
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
      <<"package", rest::binary>> ->
        raise "Package not supported"

      <<"syntax", rest::binary>> ->
        [:syntax | tokenize(rest)]

      <<"message", rest::binary>> ->
        [:message | tokenize(rest)]

      <<"oneof", rest::binary>> ->
        [:oneof | tokenize(rest)]

      <<"repeated", rest::binary>> ->
        [:repeated | tokenize(rest)]

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
          {val, _} -> raise "Invalid identifier"
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
  Reads until the first non comment or empty line and parses out
  the version. if there is no version specified in that first line,
  return :proto_2 as defined in spec
  """
  @spec parse_syntax_version(binary()) :: {:proto_2 | :proto_3, binary()}
  defp parse_syntax_version(contents) do
  end

  @doc """
  Parses the comment (including the decorators like // or /* */
  and returns the comment as well as the remaining binary
  """
  @spec read_comment(binary()) :: {binary(), binary()}
  defp read_comment(<<"//", rest::binary>>) do
    case String.split(rest, ["\r", "\n"], parts: 2) do
      [comment, rest] -> {"//" <> comment, rest}
      [comment] -> {"//" <> comment, ""}
    end
  end

  defp read_comment(<<"/*", rest::binary>>) do
    case String.split(rest, "*/", parts: 2) do
      [comment, rest] -> {"/*" <> comment <> "*/", rest}
      [comment] -> raise "Unterminated block comment"
    end
  end
end
