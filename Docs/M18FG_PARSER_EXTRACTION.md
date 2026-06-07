# M18FG Parser extraction and split

M18FG extracts the parser from `Tools/M10GDriver/Program.cs` into `Tools/M10GDriver/Parser/` using nested `partial` classes.

This is a behavior-preserving refactor. The parser remains nested under `Program` as `Program.Parser`, but its members are grouped by responsibility:

- `Parser.Core.cs`: fields, constructor, parse entry, local parser records.
- `Parser.Statements.cs`: top-level statement dispatch, file/window/function/flow statement handling.
- `Parser.Declarations.cs`: canonical declarations, literals, colors and symbol reference formatting.
- `Parser.TypeSystem.cs`: type checks, conversion helpers, formatting, matrices/quaternions/geometry storage helpers.
- `Parser.Operations.cs`: operators, scalar/vector/component/curve operations.
- `Parser.MathFunctions.cs`: matrix/transform/random/noise/coordinate math function dispatch.
- `Parser.GeometryFunctions.cs`: vector/quaternion/complex/geometry dispatch and geometry algorithms.
- `Parser.AdvancedMath.cs`: advanced/scalar/vector function parsing.
- `Parser.SymbolsFlow.cs`: symbol table, compile-time blocks and conditions.
- `Parser.Expressions.cs`: expression parser.
- `Parser.Helpers.cs`: token helpers and parser utility functions.

DX12/style work should add new parser code to a targeted parser file instead of expanding `Program.cs`.
