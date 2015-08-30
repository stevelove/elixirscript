defmodule ElixirScript.Translator do
  @moduledoc """
  Translates the given Elixir AST into JavaScript AST
  """
  alias ElixirScript.Translator.Primitive
  alias ElixirScript.Translator.Assignment
  alias ElixirScript.Translator.Map
  alias ElixirScript.Translator.Struct
  alias ElixirScript.Translator.Raise
  alias ElixirScript.Translator.Function
  alias ElixirScript.Translator.Capture
  alias ElixirScript.Translator.Expression
  alias ElixirScript.Translator.Import
  alias ElixirScript.Translator.If
  alias ElixirScript.Translator.Cond
  alias ElixirScript.Translator.Case
  alias ElixirScript.Translator.For
  alias ElixirScript.Translator.Try
  alias ElixirScript.Translator.Block
  alias ElixirScript.Translator.Module
  alias ElixirScript.Translator.Utils
  alias ElixirScript.Translator.Bitstring
  alias ElixirScript.Translator.Receive
  alias ElixirScript.Translator.Quote
  alias ElixirScript.Translator.Kernel, as: ExKernel

  @doc """
  Translates Elixir AST to JavaScript AST
  """
  def translate(ast, env \\ __ENV__) do
    do_translate(ast, env)
  end

  defp do_translate(ast, env) when is_number(ast) or is_binary(ast) or is_boolean(ast) or is_nil(ast) do
    Primitive.make_literal(ast)
  end

  defp do_translate(ast, env) when is_atom(ast) do
    Primitive.make_atom(ast)
  end

  defp do_translate(ast, env) when is_list(ast) do
    Primitive.make_list(ast, env)
  end

  defp do_translate({ one, two }, env) do
    Primitive.make_tuple({one, two}, env)
  end

  defp do_translate({:&, [], [number]}, env) when is_number(number) do
    Primitive.make_identifier(String.to_atom("__#{number}"))
  end

  defp do_translate({:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, module_name}, function_name]}, _, []}, arity]}]}, env) do
    function_name = Utils.filter_name(function_name)
    Capture.make_capture(List.last(module_name), function_name, arity, env)
  end

  defp do_translate({:&, _, [{:/, _, [{function_name, _, _}, arity]}]}, env) do
    function_name = Utils.filter_name(function_name)
    Capture.make_capture(function_name, arity, env)
  end

  defp do_translate({:&, _, body}, env) do
    params = Capture.find_value_placeholders(body) |> List.flatten
    Function.make_anonymous_function([{:->, [], [params, body]}], env)
  end

  defp do_translate({:@, _, [{name, _, [value]}]}, env) do
    name = Utils.filter_name(name)
    Module.make_attribute(name, value, env)
  end

  defp do_translate({:@, _, [{name, _, _}]}, env) do
    name = Utils.filter_name(name)
    Primitive.make_identifier(name)
  end

  defp do_translate({:%, _, [alias_info, data]}, env) do
    {_, _, name} = alias_info
    {_, _, data} = data
    Struct.make_struct(name, data)
  end

  defp do_translate({:%{}, _, [{:|, _, [map, data]}]}, env) do
    Map.make_map_update(map, data);
  end

  defp do_translate({:%{}, _, properties}, env) do
    Map.make_object(properties)
  end

  defp do_translate({:<<>>, _, elements}, env) do
    is_interpolated_string = Enum.all?(elements, fn(x) -> 
      case x do
        b when is_binary(b) ->
          true
        {:::, _, [_target, {:binary, _, _}]} ->
          true
        _ ->
          false
      end
    end)

    case is_interpolated_string do
      true ->
        Bitstring.make_interpolated_string(elements)
      _ ->
        Bitstring.make_bitstring(elements)
    end
  end

  defp do_translate({{:., _, [Access, :get]}, _, [target, property]}, env) do
    Map.make_get_property(target, property)
  end

  defp do_translate({:., _, [module_name, function_name]} = ast, env) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      Function.make_function_or_property_call(module_name, function_name, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [module_name, function_name]}, _, [] } = ast, env) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      Function.make_function_or_property_call(module_name, function_name, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [{:__aliases__, _, module_name}]}, _, params} = ast, env) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      Function.make_function_call(hd(module_name), params, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [module_name, function_name]}, _, params } = ast, env) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      Function.make_function_call(module_name, function_name, params, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({:_, _, _}, env) do
    Primitive.make_identifier(:undefined)
  end

  defp do_translate({:__aliases__, _, aliases}, env) do
    Primitive.make_identifier(aliases)
  end

  defp do_translate({:__block__, _, expressions }, env) do
    Block.make_block(expressions)
  end

  defp do_translate({:__DIR__, _, _expressions }, env) do
    ExKernel.make___DIR__()
  end

  defp do_translate({:try, _, [ blocks ]}, env) do
    Try.make_try(blocks, env)
  end

  defp do_translate({:receive, _, [expressions] }, env) do
    Receive.make_receive(expressions, env);
  end

  defp do_translate({:super, _, _expressions }, env) do
    raise ElixirScript.UnsupportedError, :super
  end

  defp do_translate({:__CALLER__, _, _expressions }, env) do
    raise ElixirScript.UnsupportedError, :__CALLER__
  end

  defp do_translate({:__ENV__, _, _expressions }, env) do
    raise ElixirScript.UnsupportedError, :__ENV__
  end

  defp do_translate({:quote, _, [[do: expr]]}, env) do
    Quote.make_quote([], expr)
  end

  defp do_translate({:quote, _, [opts, [do: expr]]}, env) do
    Quote.make_quote(opts, expr)
  end

  defp do_translate({:import, _, [{:__aliases__, _, module_name_list}]}, env) do
    Import.make_import(module_name_list, [])
  end

  defp do_translate({:import, _, [{:__aliases__, _, module_name_list}, options ]}, env) do
    Import.make_import(module_name_list, options)
  end

  defp do_translate({:alias, _, [alias_info, options]}, env) do
    Import.make_alias_import(alias_info, options)
  end

  defp do_translate({:alias, _, [alias_info]}, env) do
    Import.make_alias_import(alias_info, [])
  end

  defp do_translate({:require, _, [alias_info, options]}, env) do
    Import.make_alias_import(alias_info, options)
  end

  defp do_translate({:require, _, [alias_info]}, env) do
    Import.make_alias_import(alias_info, [])
  end

  defp do_translate({:case, _, [condition, [do: clauses]]}, env) do
    Case.make_case(condition, clauses, env)
  end

  defp do_translate({:cond, _, [[do: clauses]]}, env) do
    Cond.make_cond(clauses)
  end

  defp do_translate({:for, _, generators}, env) do
    For.make_for(generators, env)
  end

  defp do_translate({:fn, _, clauses}, env) do
    Function.make_anonymous_function(clauses, env)
  end

  defp do_translate({:.., _, [first, last]}, env) do
    ExKernel.make_range(first, last)
  end

  defp do_translate({:{}, _, elements}, env) do
    Primitive.make_tuple(elements, env)
  end

  defp do_translate({operator, _, [value]}, env) when operator in [:-, :!] do
    Expression.make_unary_expression(operator, value, env)
  end

  defp do_translate({:=, _, [left, right]}, env) do
    Assignment.make_assignment(left, right, env)
  end

  defp do_translate({:<>, _, [left, right]}, env) do
    Expression.make_binary_expression(:+, left, right, env)
  end

  defp do_translate({:++, _, [left, right]}, env) do
    ExKernel.concat_lists(left, right)
  end

  defp do_translate({operator, _, [left, right]}, env) when operator in [:+, :-, :/, :*, :==, :!=, :&&, :||, :>, :<, :>=, :<=, :===] do
    Expression.make_binary_expression(operator, left, right, env)
  end

  defp do_translate({:and, _, [left, right]}, env) do
    Expression.make_binary_expression(:&&, left, right, env)
  end

  defp do_translate({:or, _, [left, right]}, env) do
    Expression.make_binary_expression(:||, left, right, env)
  end

  defp do_translate({function, _, [{:when, _, [{name, _, _params} | _guards] }, [do: _body]] } = ast, env) when function in [:def, :defp] do
    Function.process_function(Utils.filter_name(name), [ast], env)
  end

  defp do_translate({function, _, [{name, _, _params}, [do: _body]]} = ast, env) when function in [:def, :defp] do
    Function.process_function(Utils.filter_name(name), [ast], env)
  end

  defp do_translate({:defstruct, _, attributes}, env) do
    Struct.make_defstruct(attributes)
  end

  defp do_translate({:defexception, _, attributes}, env) do
    Struct.make_defexception(attributes)
  end

  defp do_translate({:raise, _, [alias_info, attributes]}, env) do
    {_, _, name} = alias_info

    Raise.throw_error(name, attributes)
  end

  defp do_translate({:raise, _, [message]}, env) do
    Raise.throw_error(message)
  end

  defp do_translate({:if, _, _} = ast, env) do
    Macro.expand(ast, env)
    |> translate
  end

  defp do_translate({:defmodule, _, [{:__aliases__, _, module_name_list}, [do: body]]}, env) do
    Module.make_module(module_name_list, body, env)
  end

  defp do_translate({:|>, _, [left, right]}, env) do
    case right do
      {{:., meta, [module, fun]}, meta2, params} ->
        translate({{:., meta, [module, fun]}, meta2, [left] ++ params})  
      {fun, meta, params} ->
        translate({fun, meta, [left] ++ params})     
    end
  end

  defp do_translate({name, metadata, params} = ast, env) when is_list(params) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      name = Utils.filter_name(name)

      case metadata[:import] do
        Kernel ->
          Function.make_function_call(:Kernel, name, params, env)
        _ ->
          Function.make_function_call(name, params, env)        
      end
    else
      translate(expanded_ast)
    end
  end

  defp do_translate({ name, _, _ }, env) do
    name = Utils.filter_name(name)   
    Primitive.make_identifier(name)
  end

end
