using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Helpers.

        string ExpectName(string what)
        {
            if (CurrentIs("STRING") || CurrentIs("IDENT"))
                return Advance().Value;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected {what}.");
        }

        bool CurrentWordIs(string value)
            => (Current.Type == "KEYWORD" || Current.Type == "IDENT") && Current.Value == value;

        void ExpectWord(string value, string code, string message)
        {
            if ((Current.Type == "KEYWORD" || Current.Type == "IDENT") && Current.Value == value)
            {
                Advance();
                return;
            }
            throw new CompileError("PARSE", code, Current.Line, Current.Column, message);
        }

        void ExpectKeyword(string value)
        {
            if (Current.Type == "KEYWORD" && Current.Value == value)
            {
                Advance();
                return;
            }
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected keyword \"{value}\".");
        }

        Token Expect(string type, string what)
        {
            if (CurrentIs(type))
                return Advance();
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, $"Expected {what}.");
        }

        void ExpectLine()
        {
            if (CurrentIs("NEWLINE"))
            {
                Advance();
                return;
            }
            if (CurrentIs("EOF"))
                return;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected end of line.");
        }

        void ExpectLineOrEof()
        {
            if (CurrentIs("NEWLINE"))
            {
                Advance();
                return;
            }
            if (CurrentIs("EOF"))
                return;
            throw new CompileError("PARSE", "P001", Current.Line, Current.Column, "Expected end of line.");
        }

        void SkipNewlines()
        {
            while (CurrentIs("NEWLINE"))
                Advance();
        }

        bool IsEndProgram() => IsKeyword("end") && PeekKeyword("program");

        bool IsEndIf() => IsKeyword("end") && PeekKeyword("if");

        bool IsEndWhile() => IsKeyword("end") && PeekKeyword("while");

        bool IsEndSwitch() => CurrentWordIs("end") && PeekWord("switch");

        bool IsRuntimeSwitchBodyBoundary() => CurrentWordIs("case") || CurrentWordIs("default") || IsEndSwitch();

        bool IsExpressionEnd() => CurrentIs("NEWLINE") || CurrentIs("EOF") || CurrentIs("RPAREN") || CurrentIs("RBRACKET") || IsKeyword("to") || IsKeyword("from") || IsKeyword("by") || IsKeyword("else") || IsKeyword("end");

        static bool IsSymbolName(string value)
        {
            if (string.IsNullOrWhiteSpace(value))
                return false;
            if (!(char.IsLetter(value[0]) || value[0] == '_'))
                return false;
            for (var i = 1; i < value.Length; i++)
                if (!(char.IsLetterOrDigit(value[i]) || value[i] == '_'))
                    return false;
            return true;
        }

        bool PeekWord(string value)
            => PeekWord(value, 1);

        bool PeekWord(string value, int offset)
        {
            var next = _pos + offset;
            return next < _tokens.Count && (_tokens[next].Type == "KEYWORD" || _tokens[next].Type == "IDENT") && _tokens[next].Value == value;
        }

        bool PeekKeyword(string value)
            => PeekKeyword(value, 1);

        bool PeekKeyword(string value, int offset)
        {
            var next = _pos + offset;
            return next < _tokens.Count && _tokens[next].Type == "KEYWORD" && _tokens[next].Value == value;
        }

        bool PeekString(int offset)
        {
            var next = _pos + offset;
            return next < _tokens.Count && _tokens[next].Type == "STRING";
        }

        bool PeekType(string type)
        {
            var next = _pos + 1;
            return next < _tokens.Count && _tokens[next].Type == type;
        }

        bool IsKeyword(string value) => Current.Type == "KEYWORD" && Current.Value == value;

        bool CurrentIs(string type) => Current.Type == type;

        Token Current => _tokens[Math.Min(_pos, _tokens.Count - 1)];

        Token Advance() => _tokens[_pos++];

    }
}
