using System.Collections.Generic;

record Token(string Type, string Value, int Line, int Column);
record VarInfo(string Type, string Value, bool IsConst = false, bool IsRuntime = false);
record ExprResult(string Type, string Value, string Repr);
record FileValue(string Kind, string Value);
record CompareResult(bool Value, string Repr);
record RuntimeAction(string Op, string Path, string ValueKind, string Value, string Target);
record AstModel(string Program, List<(string Name, string Type, string Value)> Vars, string Title, string TitleExpr, string TitleCommand, string Message, string MessageExpr, string MessageCommand, int ExitCode, string FinalCommand, List<string> Flow, List<RuntimeAction> RuntimeActions);
