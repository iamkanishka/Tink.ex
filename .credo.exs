%{
  configs: [
    %{
      name: "default",
      files: %{
        included: [
          "lib/",
          "test/",
          "config/"
        ],
        excluded: [~r"/_build/", ~r"/deps/", ~r"/node_modules/"]
      },
      plugins: [],
      requires: [],
      strict: true,
      parse_timeout: 10_000,
      color: true,
      checks: %{
        enabled: [
          # ---------------------------------------------------------------
          # Consistency
          # ---------------------------------------------------------------
          {Credo.Check.Consistency.ExceptionNames, []},
          {Credo.Check.Consistency.LineEndings, []},
          {Credo.Check.Consistency.ParameterPatternMatching, []},
          {Credo.Check.Consistency.SpaceAroundOperators, []},
          {Credo.Check.Consistency.SpaceInParentheses, []},
          {Credo.Check.Consistency.TabsOrSpaces, []},

          # ---------------------------------------------------------------
          # Design
          # ---------------------------------------------------------------
          {Credo.Check.Design.AliasUsage,
           [priority: :low, if_nested_deeper_than: 2, if_called_more_often_than: 2]},
          {Credo.Check.Design.TagFIXME, []},
          # TODOs are allowed but do not fail CI
          {Credo.Check.Design.TagTODO, [exit_status: 0]},

          # ---------------------------------------------------------------
          # Readability
          # ---------------------------------------------------------------
          {Credo.Check.Readability.AliasOrder, []},
          {Credo.Check.Readability.FunctionNames, []},
          {Credo.Check.Readability.LargeNumbers, []},
          # Match .formatter.exs line_length: 120
          {Credo.Check.Readability.MaxLineLength, [priority: :low, max_length: 120]},
          {Credo.Check.Readability.ModuleAttributeNames, []},
          {Credo.Check.Readability.ModuleDoc, []},
          {Credo.Check.Readability.ModuleNames, []},
          {Credo.Check.Readability.ParenthesesInCondition, []},
          {Credo.Check.Readability.ParenthesesOnZeroArityDefs, []},
          {Credo.Check.Readability.PipeIntoAnonymousFunctions, []},
          {Credo.Check.Readability.PredicateFunctionNames, []},
          {Credo.Check.Readability.PreferImplicitTry, []},
          {Credo.Check.Readability.RedundantBlankLines, []},
          {Credo.Check.Readability.Semicolons, []},
          {Credo.Check.Readability.SpaceAfterCommas, []},
          {Credo.Check.Readability.StringSigils, []},
          {Credo.Check.Readability.TrailingBlankLine, []},
          {Credo.Check.Readability.TrailingWhiteSpace, []},
          {Credo.Check.Readability.UnnecessaryAliasExpansion, []},
          {Credo.Check.Readability.VariableNames, []},
          {Credo.Check.Readability.WithSingleClause, []},

          # ---------------------------------------------------------------
          # Refactoring
          # ---------------------------------------------------------------
          {Credo.Check.Refactor.Apply, []},
          {Credo.Check.Refactor.CondStatements, []},
          # Tink service modules can be moderately complex — ceiling at 15
          {Credo.Check.Refactor.CyclomaticComplexity, [max_complexity: 15]},
          # Some API builder functions take many params — ceiling at 8
          {Credo.Check.Refactor.FunctionArity, [max_arity: 8]},
          {Credo.Check.Refactor.LongQuoteBlocks, []},
          {Credo.Check.Refactor.MatchInCondition, []},
          {Credo.Check.Refactor.MapJoin, []},
          {Credo.Check.Refactor.NegatedConditionsInUnless, []},
          {Credo.Check.Refactor.NegatedConditionsWithElse, []},
          {Credo.Check.Refactor.Nesting, [max_nesting: 3]},
          {Credo.Check.Refactor.UnlessWithElse, []},
          {Credo.Check.Refactor.WithClauses, []},
          {Credo.Check.Refactor.FilterFilter, []},
          {Credo.Check.Refactor.RejectReject, []},
          {Credo.Check.Refactor.RedundantWithClauseResult, []},

          # ---------------------------------------------------------------
          # Warnings
          # ---------------------------------------------------------------
          # Allowed for compile-time pool/transport opts in Application
          # (see application.ex @env / @pool_count / @default_pool_size).
          # Suppress only for that file; all other modules are flagged.
          {Credo.Check.Warning.ApplicationConfigInModuleAttribute, []},
          {Credo.Check.Warning.BoolOperationOnSameValues, []},
          {Credo.Check.Warning.ExpensiveEmptyEnumCheck, []},
          {Credo.Check.Warning.IExPry, []},
          {Credo.Check.Warning.IoInspect, []},
          {Credo.Check.Warning.OperationOnSameValues, []},
          {Credo.Check.Warning.OperationWithConstantResult, []},
          {Credo.Check.Warning.RaiseInsideRescue, []},
          {Credo.Check.Warning.SpecWithStruct, []},
          {Credo.Check.Warning.WrongTestFileExtension, []},
          {Credo.Check.Warning.UnusedEnumOperation, []},
          {Credo.Check.Warning.UnusedFileOperation, []},
          {Credo.Check.Warning.UnusedKeywordOperation, []},
          {Credo.Check.Warning.UnusedListOperation, []},
          {Credo.Check.Warning.UnusedPathOperation, []},
          {Credo.Check.Warning.UnusedRegexOperation, []},
          {Credo.Check.Warning.UnusedStringOperation, []},
          {Credo.Check.Warning.UnusedTupleOperation, []},
          {Credo.Check.Warning.UnsafeExec, []}
        ],
        disabled: [
          # ---------------------------------------------------------------
          # Disabled — controversial or incompatible with Tink conventions
          # ---------------------------------------------------------------

          # AliasAs — not used in this codebase
          {Credo.Check.Readability.AliasAs, []},

          # SinglePipe — many Tink helpers use single-element pipes for
          # readability and future extensibility
          {Credo.Check.Readability.SinglePipe, []},

          # Specs — @spec annotations are enforced by Dialyzer, not Credo
          {Credo.Check.Readability.Specs, []},

          # StrictModuleLayout — Tink places @moduledoc after use/import
          # blocks which conflicts with strict layout ordering
          {Credo.Check.Readability.StrictModuleLayout, []},

          # WithCustomTaggedTuple — {:ok, _} / {:error, _} convention used
          # throughout; custom tagged tuples are intentional
          {Credo.Check.Readability.WithCustomTaggedTuple, []},

          # ABCSize — superseded by CyclomaticComplexity above
          {Credo.Check.Refactor.ABCSize, []},

          # AppendSingleItem — pattern used deliberately in build helpers
          {Credo.Check.Refactor.AppendSingleItem, []},

          # DoubleBooleanNegation — used intentionally in guard clauses
          {Credo.Check.Refactor.DoubleBooleanNegation, []},

          # ModuleDependencies — too noisy for a multi-module SDK
          {Credo.Check.Refactor.ModuleDependencies, []},

          # NegatedIsNil — `not is_nil(x)` preferred over `x != nil` in guards
          {Credo.Check.Refactor.NegatedIsNil, []},

          # PipeChainStart — pipe chains sometimes start with a variable
          {Credo.Check.Refactor.PipeChainStart, []},

          # VariableRebinding — used in Auth token refresh flows
          {Credo.Check.Refactor.VariableRebinding, []},

          # LazyLogging — Logger calls in Tink are always guarded by config
          {Credo.Check.Warning.LazyLogging, []},

          # LeakyEnvironment — Mix.env() usage is isolated to application.ex
          # at compile time via @env module attribute; no runtime leakage
          {Credo.Check.Warning.LeakyEnvironment, []},

          # MapGetUnsafePass — pattern used intentionally with known-shape maps
          {Credo.Check.Warning.MapGetUnsafePass, []},

          # MixEnv — Mix.env() is captured into @env at compile time only
          {Credo.Check.Warning.MixEnv, []},

          # UnsafeToAtom — Tink API keys are from controlled provider configs
          {Credo.Check.Warning.UnsafeToAtom, []}
        ]
      }
    }
  ]
}
