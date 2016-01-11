defmodule Alchemist.Code.MetadataBuilder do

  def build(ast) do
    acc = %{
      modules: [:Elixir],
      scopes:  [:Elixir],
      imports: [[]],
      aliases: [[]],
      vars:    [[]],
      mods_funs_to_lines: %{},
      lines_to_context: %{}
    }
    traverse(ast, acc, &pre/2, &post/2)
  end

  defp pre({:defmodule, [line: line], [{:__aliases__, _, module}, _]} = ast, acc) do
    modules_reversed = :lists.reverse(module)
    modules = modules_reversed ++ acc.modules
    scopes  = modules_reversed ++ acc.scopes
    imports = [[]|acc.imports]
    vars    = [[]|acc.vars]

    current_module = modules |> :lists.reverse |> Module.concat
    mods_funs_to_lines = Map.put(acc.mods_funs_to_lines, {current_module, nil, nil}, line)

    aliases = acc.aliases

    # TODO: Context.add_alias_to_current_scope(context)
    # Context.add_import_to_current_scope(context)
    # Context.create_new_scope(context)
    # ...

    # create alias for the module in the current scope
    if length(modules) > 2 do
      alias_tuple = {Module.concat([hd(modules)]), current_module}
      [aliases_from_scope|other_aliases] = acc.aliases
      aliases = [[alias_tuple|aliases_from_scope]|other_aliases]
    end

    # add new empty list of aliases for the new scope
    aliases = [[]|aliases]

    {ast, %{acc | modules: modules, scopes: scopes, imports: imports, aliases: aliases, vars: vars, mods_funs_to_lines: mods_funs_to_lines}}
  end

  defp pre({def_fun, meta, [{:when, _, [head|_]}, body]}, acc) when def_fun in [:def, :defp] do
    pre({:def, meta, [head, body]}, acc)
  end

  defp pre({def_fun, [line: line], [{name, _, params}, _body]} = ast, acc) when def_fun in [:def, :defp] do
    current_module  = acc.modules |> :lists.reverse |> Module.concat
    current_imports = acc.imports |> :lists.reverse |> List.flatten
    current_aliases = acc.aliases |> :lists.reverse |> List.flatten

    scopes  = [name|acc.scopes]
    imports = [[]|acc.imports]
    aliases = [[]|acc.aliases]
    vars    = [[]|acc.vars]

    mods_funs_to_lines = Map.put(acc.mods_funs_to_lines, {current_module, name, length(params || [])}, line)
    if !Map.has_key?(acc.mods_funs_to_lines, {current_module, name, nil}) do
      mods_funs_to_lines = Map.put(acc.mods_funs_to_lines, {current_module, name, nil}, line)
    end
    lines_to_context = Map.put(acc.lines_to_context, line, %{imports: current_imports, aliases: current_aliases, module: current_module})

    {ast, %{acc | scopes: scopes, imports: imports, aliases: aliases, vars: vars, mods_funs_to_lines: mods_funs_to_lines, lines_to_context: lines_to_context}}
  end

  # Macro without body. Ex: Kernel.SpecialForms.import
  defp pre({:defmacro, meta, [head]}, acc) do
    pre({:defmacro, meta, [head,nil]}, acc)
  end

  defp pre({:defmacro, meta, args}, acc) do
    pre({:def, meta, args}, acc)
  end

  # import without options
  defp pre({:import, meta, [module_info]}, acc) do
    pre({:import, meta, [module_info, []]}, acc)
  end

  defp pre({:import, [line: line], [{_, _, module_atoms = [mod|_]}, _opts]} = ast, acc) when is_atom(mod) do
    current_module  = acc.modules |> :lists.reverse |> Module.concat
    current_imports = acc.imports |> :lists.reverse |> List.flatten
    current_aliases = acc.aliases |> :lists.reverse |> List.flatten
    lines_to_context = Map.put(acc.lines_to_context, line, %{imports: current_imports, aliases: current_aliases, module: current_module})

    module = Module.concat(module_atoms)
    [imports_from_scope|other_imports] = acc.imports
    imports = [[module|imports_from_scope]|other_imports]

    {ast, %{acc | imports: imports, lines_to_context: lines_to_context}}
  end

  # alias without options
  defp pre({:alias, [line: line], [{:__aliases__, _, module_atoms = [mod|_]}]} = ast, acc) when is_atom(mod) do
    alias_tuple = {Module.concat([List.last(module_atoms)]), Module.concat(module_atoms)}
    do_alias(ast, line, alias_tuple, acc)
  end

  defp pre({:alias, [line: line], [{_, _, module_atoms = [mod|_]}, [as: {:__aliases__, _, alias_atoms = [al|_]}]]} = ast, acc) when is_atom(mod) and is_atom(al) do
    alias_tuple = {Module.concat(alias_atoms), Module.concat(module_atoms)}
    do_alias(ast, line, alias_tuple, acc)
  end

  defp pre({var, [line: _], context} = ast, acc) when is_atom(var) and context in [nil, Elixir] do
    scope = hd(acc.scopes) |> Atom.to_string
    [vars_from_scope|other_vars] = acc.vars

    vars_from_scope =
      if var in vars_from_scope do
        vars_from_scope
      else
        case Atom.to_string(var) do
          "_" <> _ -> vars_from_scope
          ^scope   -> vars_from_scope
          _        -> [var|vars_from_scope]
        end
      end

    {ast, %{acc | vars: [vars_from_scope|other_vars]}}
  end

  defp pre({_, [line: line], _} = ast, acc) do
    current_module  = acc.modules |> :lists.reverse |> Module.concat
    current_imports = acc.imports |> :lists.reverse |> List.flatten
    current_aliases = acc.aliases |> :lists.reverse |> List.flatten
    [vars_from_scope|_] = acc.vars

    lines_to_context = Map.put(acc.lines_to_context, line, %{imports: current_imports, aliases: current_aliases, module: current_module, vars: vars_from_scope})

    {ast, %{acc | lines_to_context: lines_to_context}}
  end

  defp pre(ast, acc) do
    # IO.puts "No line"
    {ast, acc}
  end

  defp do_alias(ast, line, alias_tuple, acc) do
    current_module  = acc.modules |> :lists.reverse |> Module.concat
    current_imports = acc.imports |> :lists.reverse |> List.flatten
    current_aliases = acc.aliases |> :lists.reverse |> List.flatten
    lines_to_context = Map.put(acc.lines_to_context, line, %{imports: current_imports, aliases: current_aliases, module: current_module})

    [aliases_from_scope|other_aliases] = acc.aliases
    aliases = [[alias_tuple|aliases_from_scope]|other_aliases]

    {ast, %{acc | aliases: aliases, lines_to_context: lines_to_context}}
  end

  defp post({:defmodule, _, [{:__aliases__, _, module}, _]} = ast, acc) do
    outer_mods   = Enum.drop(acc.modules, length(module))
    outer_scopes = Enum.drop(acc.scopes, length(module))
    {ast, %{acc | modules: outer_mods, scopes: outer_scopes, imports: tl(acc.imports), aliases: tl(acc.aliases), vars: tl(acc.vars)}}
  end

  defp post({def_fun, meta, [{:when, _, [head|_]}, body]}, acc) when def_fun in [:def, :defp] do
    pre({:def, meta, [head, body]}, acc)
  end

  defp post({def_fun, [line: _line], [{_name, _, _params}, _]} = ast, acc) when def_fun in [:def, :defp] do
    {ast, %{acc | scopes: tl(acc.scopes), imports: tl(acc.imports), aliases: tl(acc.aliases), vars: tl(acc.vars)}}
  end

  # Macro without body. Ex: Kernel.SpecialForms.import
  defp post({:defmacro, meta, [head]}, acc) do
    post({:def, meta, [head,nil]}, acc)
  end

  defp post({:defmacro, meta, args}, acc) do
    post({:def, meta, args}, acc)
  end

  defp post(ast, acc) do
    {ast, acc}
  end

  # From: https://github.com/elixir-lang/elixir/blob/bd3332c8484f791eba8c7db875cebdcd34d8112b/lib/elixir/lib/macro.ex#L175
  defp traverse(ast, acc, pre, post) when is_function(pre, 2) and is_function(post, 2) do
    {ast, acc} = pre.(ast, acc)
    do_traverse(ast, acc, pre, post)
  end

  defp do_traverse({form, meta, args}, acc, pre, post) do
    unless is_atom(form) do
      {form, acc} = pre.(form, acc)
      {form, acc} = do_traverse(form, acc, pre, post)
    end

    unless is_atom(args) do
      {args, acc} = Enum.map_reduce(args, acc, fn x, acc ->
        {x, acc} = pre.(x, acc)
        do_traverse(x, acc, pre, post)
      end)
    end

    post.({form, meta, args}, acc)
  end

  defp do_traverse({left, right}, acc, pre, post) do
    {left, acc} = pre.(left, acc)
    {left, acc} = do_traverse(left, acc, pre, post)
    {right, acc} = pre.(right, acc)
    {right, acc} = do_traverse(right, acc, pre, post)
    post.({left, right}, acc)
  end

  defp do_traverse(list, acc, pre, post) when is_list(list) do
    {list, acc} = Enum.map_reduce(list, acc, fn x, acc ->
      {x, acc} = pre.(x, acc)
      do_traverse(x, acc, pre, post)
    end)
    post.(list, acc)
  end

  defp do_traverse(x, acc, _pre, post) do
    post.(x, acc)
  end

end