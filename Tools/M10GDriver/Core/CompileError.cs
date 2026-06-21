using System;

sealed class CompileError : Exception
{
    public string Stage { get; }
    public string Code { get; }
    public int Line { get; }
    public int Column { get; }

    public CompileError(string stage, string code, int line, int column, string message) : base(message)
    {
        Stage = stage;
        Code = code;
        Line = line;
        Column = column;
    }

    public string Format()
    {
        if (Line > 0 && Column > 0)
            return $"Error {Code} at line {Line}, column {Column}:\r\n{Message}\r\n";
        return $"Error {Code}:\r\n{Message}\r\n";
    }
}
