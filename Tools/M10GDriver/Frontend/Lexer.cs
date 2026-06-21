using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

static partial class Program
{
    static List<Token> Lex(string source)
    {
        var tokens = new List<Token>();
        var i = 0;
        var line = 1;
        var col = 1;

        while (i < source.Length)
        {
            var ch = source[i];

            if (ch is ' ' or '\t')
            {
                i++;
                col++;
                continue;
            }

            if (ch == '\r' || ch == '\n')
            {
                var startCol = col;
                if (ch == '\r' && i + 1 < source.Length && source[i + 1] == '\n')
                    i += 2;
                else
                    i++;
                tokens.Add(new Token("NEWLINE", "", line, startCol));
                line++;
                col = 1;
                continue;
            }

            if (ch == '/' && i + 1 < source.Length && source[i + 1] == '/')
            {
                while (i < source.Length && source[i] != '\r' && source[i] != '\n')
                {
                    i++;
                    col++;
                }
                continue;
            }

            if (ch == '/' && IsStatementSlash(source, i))
                throw new CompileError("LEX", "L001", line, col, "Unknown character '/'.");

            if (ch == '"')
            {
                var startLine = line;
                var startCol = col;
                i++;
                col++;
                var sb = new StringBuilder();
                while (i < source.Length && source[i] != '"')
                {
                    if (source[i] == '\r' || source[i] == '\n')
                        throw new CompileError("LEX", "L002", startLine, startCol, "Unterminated string.");
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                if (i >= source.Length)
                    throw new CompileError("LEX", "L002", startLine, startCol, "Unterminated string.");
                i++;
                col++;
                tokens.Add(new Token("STRING", sb.ToString(), startLine, startCol));
                continue;
            }

            if (char.IsLetter(ch) || ch == '_')
            {
                var startLine = line;
                var startCol = col;
                var sb = new StringBuilder();
                while (i < source.Length && (char.IsLetterOrDigit(source[i]) || source[i] == '_'))
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                var word = sb.ToString();
                if (word is "true" or "false")
                    tokens.Add(new Token("BOOL", word, startLine, startCol));
                else if (word is "program" or "let" or "be" or "title" or "message" or "text" or "show" or "set" or "to" or "exit" or "blend" or "mix" or "code" or "end" or "if" or "else" or "is" or "not" or "define" or "local" or "string" or "int" or "bool" or "var" or "called" or "rename" or "print" or "const" or "float" or "double" or "vec2" or "vec3" or "vec4" or "mat4" or "transform" or "quat" or "rect" or "circle" or "segment" or "line" or "ray" or "sphere" or "aabb" or "plane" or "complex" or "color" or "angle" or "deg" or "rad" or "while" or "switch" or "case" or "default" or "from" or "add" or "remove" or "multiply" or "by" or "divide" or "function" or "call" or "return" or "and" or "or" or "write" or "file" or "with" or "use" or "load" or "command" or "arg" or "count" or "window" or "resolution" or "resizable" or "run" or "of" or "when" or "closed" or "key" or "pressed" or "close" or "style" or "for")
                    tokens.Add(new Token("KEYWORD", word, startLine, startCol));
                else
                    tokens.Add(new Token("IDENT", word, startLine, startCol));
                continue;
            }

            if (char.IsDigit(ch))
            {
                var startLine = line;
                var startCol = col;
                var sb = new StringBuilder();
                while (i < source.Length && char.IsDigit(source[i]))
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                }
                if (i < source.Length && source[i] == '.')
                {
                    sb.Append(source[i]);
                    i++;
                    col++;
                    if (i >= source.Length || !char.IsDigit(source[i]))
                        throw new CompileError("LEX", "L003", startLine, startCol, "Invalid decimal literal.");
                    while (i < source.Length && char.IsDigit(source[i]))
                    {
                        sb.Append(source[i]);
                        i++;
                        col++;
                    }
                    tokens.Add(new Token("DECIMAL", sb.ToString(), startLine, startCol));
                    continue;
                }
                tokens.Add(new Token("INT", sb.ToString(), startLine, startCol));
                continue;
            }

            if (ch == '+')
            {
                tokens.Add(new Token("PLUS", "+", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '-')
            {
                tokens.Add(new Token("MINUS", "-", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '*')
            {
                tokens.Add(new Token("STAR", "*", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '/')
            {
                tokens.Add(new Token("SLASH", "/", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '%')
            {
                tokens.Add(new Token("PERCENT", "%", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '^')
            {
                tokens.Add(new Token("CARET", "^", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ':')
            {
                tokens.Add(new Token("COLON", ":", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ',')
            {
                tokens.Add(new Token("COMMA", ",", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '[')
            {
                tokens.Add(new Token("LBRACKET", "[", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ']')
            {
                tokens.Add(new Token("RBRACKET", "]", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '(')
            {
                tokens.Add(new Token("LPAREN", "(", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == ')')
            {
                tokens.Add(new Token("RPAREN", ")", line, col));
                i++;
                col++;
                continue;
            }

            if (ch == '>')
            {
                if (i + 1 < source.Length && source[i + 1] == '=')
                {
                    tokens.Add(new Token("GTE", ">=", line, col));
                    i += 2;
                    col += 2;
                }
                else
                {
                    tokens.Add(new Token("GT", ">", line, col));
                    i++;
                    col++;
                }
                continue;
            }

            if (ch == '<')
            {
                if (i + 1 < source.Length && source[i + 1] == '=')
                {
                    tokens.Add(new Token("LTE", "<=", line, col));
                    i += 2;
                    col += 2;
                }
                else
                {
                    tokens.Add(new Token("LT", "<", line, col));
                    i++;
                    col++;
                }
                continue;
            }

            if (char.IsControl(ch))
                throw new CompileError("LEX", "L004", line, col, "Unexpected control character.");

            throw new CompileError("LEX", "L001", line, col, $"Unknown character '{ch}'.");
        }

        tokens.Add(new Token("EOF", "", line, col));
        return tokens;
    }

    static string TokenLine(Token t) => $"{t.Type}|{Esc(t.Value)}|{t.Line}|{t.Column}";

    static bool IsStatementSlash(string source, int index)
    {
        for (var i = index - 1; i >= 0; i--)
        {
            if (source[i] is '\r' or '\n')
                return true;
            if (source[i] is not (' ' or '\t'))
                return false;
        }
        return true;
    }
}
