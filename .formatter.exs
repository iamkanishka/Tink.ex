[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  line_length: 120,
  locals_without_parens: [
    # Ecto-style field declarations (used in type structs)
    field: 2,
    field: 3,

    # defdelegate without parens on target
    defdelegate: 2
  ]
]
