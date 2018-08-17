defmodule ExDocMarkdownFormatter.Templates do
  @moduledoc false
  require EEx

  @doc """
  Generate content from the module template for a given `node`
  """
  def module_page(module_node, nodes_map, config) do
    summary_map = module_summary(module_node)
    module_template(config, module_node, summary_map, nodes_map)
  end

  def detail_section(node, _module) do
    [
      detail_header(node),
      detail_annotations(node),
      detail_specs(node),
      detail_docs(node)
    ]
    |> Enum.map(&(&1 || ""))
    |> Enum.join()
  end

  defp detail_header(%{signature: signature, source_url: url}) do
    ["### ", signature, (url && " ([Source](#{url}))") || ""]
  end

  defp detail_annotations(%{annotations: annotations}) do
    if annotations do
      list = for annotation <- annotations, do: "(#{annotation})"
      list ++ ["\n\n"]
    end || ""
  end

  defp detail_specs(node) do
    if specs = get_specs(node) do
      list = for spec <- specs, do: "- #{spec}\n"
      list ++ ["\n"]
    end || ""
  end

  defp detail_docs(node) do
    dep_str =
      if deprecated = node.deprecated do
        "*This #{node.type} is deprecated. #{h(deprecated)}.\n\n"
      end || ""

    [dep_str, node.doc || ""]
  end

  @doc """
  Get the full specs from a function, already in HTML form.
  """
  def get_specs(%ExDoc.TypeNode{spec: spec}) do
    [spec]
  end

  def get_specs(%ExDoc.FunctionNode{specs: specs}) when is_list(specs) do
    presence(specs)
  end

  def get_specs(_node) do
    nil
  end

  @doc """
  Get defaults clauses.
  """
  def get_defaults(%{defaults: defaults}) do
    defaults
  end

  def get_defaults(_) do
    []
  end

  @doc """
  Generate a link id
  """
  def link_id(module_node), do: link_id(module_node.id, module_node.type)

  def link_id(id, type) do
    case type do
      :macrocallback -> "c:#{id}"
      :callback -> "c:#{id}"
      :type -> "t:#{id}"
      :opaque -> "t:#{id}"
      _ -> "#{id}"
    end
  end

  @doc """
  Returns the HTML formatted title for the module page.
  """
  def module_title(%{type: :task, title: title}),
    do: "mix " <> title

  def module_title(%{type: :module, title: title}),
    do: title

  def module_title(%{type: type, title: title}),
    do: title <> " <small>#{type}</small>"

  @doc """
  Gets the first paragraph of the documentation of a node. It strips
  surrounding spaces and strips traling `:` and `.`.

  If `doc` is `nil`, it returns `nil`.
  """
  @spec synopsis(String.t()) :: String.t()
  @spec synopsis(nil) :: nil

  def synopsis(nil), do: nil
  def synopsis(""), do: ""

  def synopsis(doc) when is_binary(doc) do
    doc
    |> String.split(~r/\n\s*\n/)
    |> hd()
    |> String.trim()
    |> String.replace(~r{[.:\s]+$}, "")
    |> String.trim_trailing()
  end

  defp presence([]), do: nil
  defp presence(other), do: other

  @doc false
  def h(binary) do
    escape_map = [{"&", "&amp;"}, {"<", "&lt;"}, {">", "&gt;"}, {~S("), "&quot;"}]

    Enum.reduce(escape_map, binary, fn {pattern, escape}, acc ->
      String.replace(acc, pattern, escape)
    end)
  end

  @doc false
  def enc_h(binary) do
    binary
    |> URI.encode()
    |> h()
  end

  def module_summary(module_node) do
    %{
      callbacks: Enum.filter(module_node.docs, &(&1.type in [:callback, :macrocallback])),
      functions: Enum.filter(module_node.docs, &(&1.type in [:function, :macro])),
      guards: Enum.filter(module_node.docs, &(&1.type in [:guard])),
      types: module_node.typespecs
    }
  end

  templates = [
    detail_template: [:module_node, :_module],
    footer_template: [:config],
    module_template: [:config, :module, :summary_map, :nodes_map]
  ]

  Enum.each(templates, fn {name, args} ->
    filename = Path.expand("templates/#{name}.eex", __DIR__)
    @doc false
    EEx.function_from_file(:def, name, filename, args, trim: true)
  end)
end
