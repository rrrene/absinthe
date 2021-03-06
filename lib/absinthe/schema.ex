defmodule Absinthe.Schema do
  import Absinthe.Schema.Notation

  @moduledoc """
  Define a GraphQL schema.

  See also `Absinthe.Schema.Notation` for a reference of the macros imported by
  this module available to build types for your schema.

  ## Basic Usage

  To define a schema, `use Absinthe.Schema` within
  a module. This marks your module as adhering to the
  `Absinthe.Schema` behaviour, and sets up some macros
  and utility functions for your use:

  ```
  defmodule App.Schema do
    use Absinthe.Schema

    # ... define it here!

  end
  ```

  Now, define a `query` (and optionally, `mutation`
  and `subscription`).

  We'll define a `query` that has one field, `item`, to support
  querying for an item record by its ID:

  ```
  # Just for the example. You're probably using Ecto or
  # something much more interesting than a module attribute-based
  # database!
  @fake_db %{
    "foo" => %{id: "foo", name: "Foo", value: 4},
    "bar" => %{id: "bar", name: "Bar", value: 5}
  }

  query do
    @desc "Get an item by ID"
    field :item, :item do

      @desc "The ID of the item"
      arg :id, type: :id

      resolve fn %{id: id}, _ ->
        {:ok, Map.get(@fake_db, id)}
      end
    end
  end
  ```

  For more information on object types (especially how the `resolve`
  function works above), see `Absinthe.Type.Object`.

  You may also notice we've declared that the resolved value of the field
  to be of `type: :item`. We now need to define exactly what an `:item` is,
  and what fields it contains.

  ```
  @desc "A valuable Item"
  object :item do
    field :id, :id

    @desc "The item's name"
    field :name, :string,

    field :value, :integer, description: "Recently appraised value"
  end
  ```

  We can also load types from other modules using the `import_types`
  macro:

  ```
  defmodule App.Schema do
    use Absinthe.Schema

    import_types App.Schema.Scalars
    import_types App.Schema.Objects

    # ... schema definition

  end
  ```

  Our `:item` type above could then move into `App.Schema.Objects`:

  ```
  defmodule App.Schema.Objects do
    use Absinthe.Scheme.Notation

    object :item do
      # ... type definition
    end

    # ... other objects!

  end
  ```
  """

  @typedoc """
  A module defining a schema.
  """
  @type t :: atom

  alias Absinthe.Type
  alias Absinthe.Language
  alias __MODULE__

  defmacro __using__(_opts) do
    quote do
      use Absinthe.Schema.Notation
      import unquote(__MODULE__), only: :macros
      import_types Absinthe.Type.BuiltIns
      @after_compile unquote(__MODULE__)
    end
  end

  @doc false
  def __after_compile__(env, _bytecode) do
    [
      env.module.__absinthe_errors__,
      Schema.Rule.check(env.module)
    ]
    |> List.flatten
    |> case do
      [] ->
        nil
      details ->
        raise Absinthe.Schema.Error, details
    end
  end

  @default_query_name "RootQueryType"
  @doc """
  Defines a root Query object
  """
  defmacro query(raw_attrs, [do: block]) do
    attrs = raw_attrs
    |> Keyword.put_new(:name, @default_query_name)
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :query, attrs, block)
  end

  @doc """
  Defines a root Query object
  """
  defmacro query([do: block]) do
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :query, [name: @default_query_name], block)
  end

  @default_mutation_name "RootMutationType"
  @doc """
  Defines a root Mutation object
  """
  defmacro mutation(raw_attrs, [do: block]) do
    attrs = raw_attrs
    |> Keyword.put_new(:name, @default_mutation_name)
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :mutation, attrs, block)
  end

  @doc """
  Defines a root Mutation object
  """
  defmacro mutation([do: block]) do
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :mutation, [name: @default_mutation_name], block)
  end

  @default_subscription_name "RootSubscriptionType"
  @doc """
  Defines a root Subscription object
  """
  defmacro subscription(raw_attrs, [do: block]) do
    attrs = raw_attrs
    |> Keyword.put_new(:name, @default_subscription_name)
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :subscription, attrs, block)
  end
  @doc """
  Defines a root Subscription object
  """
  defmacro subscription([do: block]) do
    Absinthe.Schema.Notation.scope(__CALLER__, :object, :subscription, [name: @default_subscription_name], block)
  end

  # Lookup a directive that in used by/available to a schema
  @doc """
  Lookup a directive.
  """
  @spec lookup_directive(t, atom | binary) :: Type.Directive.t | nil
  def lookup_directive(schema, name) do
    schema.__absinthe_directive__(name)
  end

  @doc """
  Lookup a type by name, identifier, or by unwrapping.
  """
  @spec lookup_type(atom, Type.wrapping_t | Type.t | Type.identifier_t, Keyword.t) :: Type.t | nil
  def lookup_type(schema, type, options \\ [unwrap: true]) do
    cond do
      Type.wrapped?(type) ->
        if Keyword.get(options, :unwrap) do
          lookup_type(schema, type |> Type.unwrap)
        else
          type
        end
      is_atom(type) ->
        schema.__absinthe_type__(type)
      is_binary(type) ->
        schema.__absinthe_type__(type)
      true ->
        type
    end
  end

  @doc """
  List all types on a schema
  """
  @spec types(t) :: [Type.t]
  def types(schema) do
    schema.__absinthe_types__
    |> Map.keys
    |> Enum.map(&lookup_type(schema, &1))
  end

  @doc """
  List all directives on a schema
  """
  @spec directives(t) :: [Type.Directive.t]
  def directives(schema) do
    schema.__absinthe_directives__
    |> Map.keys
    |> Enum.map(&lookup_directive(schema, &1))
  end

  @doc """
  List all implementors of an interface on a schema
  """
  @spec implementors(t, atom) :: [Type.Object.t]
  def implementors(schema, ident) when is_atom(ident) do
    schema.__absinthe_interface_implementors__
    |> Map.get(ident, [])
    |> Enum.map(&lookup_type(schema, &1))
  end
  def implementors(schema, %Type.Interface{} = iface) do
    implementors(schema, iface.__reference__.identifier)
  end

  @doc false
  @spec type_from_ast(t, Language.type_reference_t) :: Absinthe.Type.t | nil
  def type_from_ast(schema, %Language.NonNullType{type: inner_type}) do
    case type_from_ast(schema, inner_type) do
      nil -> nil
      type -> %Type.NonNull{of_type: type}
    end
  end
  def type_from_ast(schema, %Language.ListType{type: inner_type}) do
    case type_from_ast(schema, inner_type) do
      nil -> nil
      type -> %Type.List{of_type: type}
    end
  end
  def type_from_ast(schema, ast_type) do
    Schema.types(schema)
    |> Enum.find(fn
      %{name: name} ->
        name == ast_type.name
    end)
  end

end
