%{
  configs: [
    %{
      name: "default",
      files: %{included: ["lib/", "test/"], excluded: []},
      strict: true,
      color: true,
      checks: [
        {Credo.Check.Consistency.TabsOrSpaces},
        {Credo.Check.Design.AliasUsage, false},
        {Credo.Check.Readability.ModuleDoc},
        {Credo.Check.Readability.FunctionNames},
        {Credo.Check.Refactor.FunctionArity},
        {Credo.Check.Warning.IoInspect},
        {Credo.Check.Warning.UnusedEnumOperation},
        {Credo.Check.Warning.UnusedStringOperation}
      ]
    }
  ]
}
