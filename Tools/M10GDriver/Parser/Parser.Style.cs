using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;

static partial class Program
{
    sealed partial class Parser
    {
        // M19B style/design foundation.

        static readonly HashSet<string> StyleStates = new(StringComparer.Ordinal)
        {
            "hovered",
            "pressed",
            "disabled",
            "focused",
            "unfocused",
        };

        static readonly HashSet<string> StyleProperties = new(StringComparer.Ordinal)
        {
            "type",
            "color",
            "background color",
            "foreground color",
            "border color",
            "border size",
            "corner radius",
            "padding",
            "margin",
            "opacity",
            "visibility",
            "clip children",
            "font",
            "size",
        };

        static readonly HashSet<string> StyleTypeValues = new(StringComparer.Ordinal)
        {
            "rectangle",
            "rounded rectangle",
            "panel",
            "text",
            "button",
            "slider",
            "input field",
            "checkbox",
            "dropdown",
            "image",
        };

        static readonly HashSet<string> StyleColorNames = new(StringComparer.Ordinal)
        {
            "black",
            "white",
            "red",
            "green",
            "blue",
            "transparent",
            "light blue",
            "dark blue",
        };

        void ParseStyleStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "style blocks inside compile-time if are not supported in M19B.");

            ExpectKeyword("with");
            ExpectKeyword("style");
            ExpectKeyword("for");
            var targetTok = Expect("STRING", "style target name");
            var state = "default";

            if (IsKeyword("when"))
            {
                ExpectKeyword("when");
                var stateTok = ExpectStyleWord("style state");
                state = stateTok.Value;
                if (!StyleStates.Contains(state))
                    throw new CompileError("SEMANTIC", "S201", stateTok.Line, stateTok.Column, $"Unsupported style state '{state}'.");
            }

            ExpectLine();

            var blockKey = targetTok.Value + "|" + state;
            if (_styleBlocks.Contains(blockKey))
                throw new CompileError("SEMANTIC", "S202", targetTok.Line, targetTok.Column, $"Duplicate style block for '{targetTok.Value}' state '{state}'.");
            _styleBlocks.Add(blockKey);

            var seenProperties = new HashSet<string>(StringComparer.Ordinal);
            var count = 0;
            SkipNewlines();
            while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekKeyword("style")))
            {
                var propertyTok = Current;
                var property = ParseStylePropertyName();
                if (!StyleProperties.Contains(property))
                    throw new CompileError("SEMANTIC", "S203", propertyTok.Line, propertyTok.Column, $"Unknown style property '{property}'.");
                if (!seenProperties.Add(property))
                    throw new CompileError("SEMANTIC", "S204", propertyTok.Line, propertyTok.Column, $"Duplicate style property '{property}'.");

                var parsed = ParseStylePropertyValue(property, propertyTok);
                if (apply)
                    _styles.Add(new StyleProperty(targetTok.Value, state, property, parsed.Kind, parsed.Value, parsed.Unit, parsed.Source));
                count++;
                SkipNewlines();
            }

            if (!IsKeyword("end") || !PeekKeyword("style"))
                throw new CompileError("PARSE", "P200", Current.Line, Current.Column, "Expected end style.");
            ExpectKeyword("end");
            ExpectKeyword("style");
            ExpectLine();

            if (count == 0)
                throw new CompileError("SEMANTIC", "S205", targetTok.Line, targetTok.Column, $"Style block for '{targetTok.Value}' cannot be empty.");
        }

        Token ExpectStyleWord(string what)
        {
            if (Current.Type == "KEYWORD" || Current.Type == "IDENT")
                return Advance();
            throw new CompileError("PARSE", "P201", Current.Line, Current.Column, $"Expected {what}.");
        }

        string ParseStylePropertyName()
        {
            var words = new List<string>();
            while (!CurrentIs("COLON"))
            {
                if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P202", Current.Line, Current.Column, "Expected ':' after style property name.");
                if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                    throw new CompileError("PARSE", "P202", Current.Line, Current.Column, "Expected style property name.");
                words.Add(Advance().Value);
            }

            if (words.Count == 0)
                throw new CompileError("PARSE", "P202", Current.Line, Current.Column, "Expected style property name.");
            Expect("COLON", "style property separator ':'");
            return string.Join(" ", words).ToLowerInvariant();
        }

        record ParsedStyleValue(string Kind, string Value, string Unit, string Source);

        ParsedStyleValue ParseStylePropertyValue(string property, Token propertyTok)
        {
            if (CurrentIs("NEWLINE") || CurrentIs("EOF"))
                throw new CompileError("PARSE", "P203", Current.Line, Current.Column, $"Expected value for style property '{property}'.");

            return property switch
            {
                "type" => ParseStyleEnumValue(property, StyleTypeValues, "S206"),
                "visibility" => ParseStyleEnumValue(property, new HashSet<string>(StringComparer.Ordinal) { "visible", "hidden", "collapsed" }, "S207"),
                "clip children" => ParseStyleBoolValue(property),
                "opacity" => ParseStyleOpacityValue(property),
                "font" => ParseStyleFontValue(property),
                "size" => ParseStyleDimensionValue(property),
                "border size" => ParseStyleDimensionValue(property),
                "corner radius" => ParseStyleDimensionValue(property),
                "padding" => ParseStyleDimensionValue(property),
                "margin" => ParseStyleDimensionValue(property),
                "color" or "background color" or "foreground color" or "border color" => ParseStyleColorValue(property),
                _ => throw new CompileError("SEMANTIC", "S203", propertyTok.Line, propertyTok.Column, $"Unknown style property '{property}'."),
            };
        }

        ParsedStyleValue ParseStyleEnumValue(string property, HashSet<string> allowed, string errorCode)
        {
            var value = ReadStyleWordsUntilLine(property);
            var normalized = value.ToLowerInvariant();
            if (!allowed.Contains(normalized))
                throw new CompileError("SEMANTIC", errorCode, Current.Line, Current.Column, $"Unsupported {property} value '{value}'.");
            ExpectLine();
            return new ParsedStyleValue("enum", normalized, "", value);
        }

        ParsedStyleValue ParseStyleBoolValue(string property)
        {
            var token = Current;
            if (!CurrentIs("BOOL"))
                throw new CompileError("SEMANTIC", "S208", token.Line, token.Column, $"Style property '{property}' requires a boolean value.");
            Advance();
            ExpectLine();
            return new ParsedStyleValue("bool", token.Value, "", token.Value);
        }

        ParsedStyleValue ParseStyleOpacityValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S209", start.Line, start.Column, $"Style property '{property}' requires a numeric value.");
            var value = ToNumber(expr);
            if (value < 0 || value > 1)
                throw new CompileError("SEMANTIC", "S209", start.Line, start.Column, "Style opacity must be between 0 and 1.");
            ExpectLine();
            return new ParsedStyleValue("number", FormatNumber(value, "double"), "", expr.Value);
        }

        ParsedStyleValue ParseStyleDimensionValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a numeric px value.");
            var value = ToNumber(expr);
            if (value < 0)
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' cannot be negative.");
            if (!CurrentWordIs("px"))
                throw new CompileError("PARSE", "P204", Current.Line, Current.Column, $"Expected px unit for style property '{property}'.");
            Advance();
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedStyleValue("dimension", formatted, "px", formatted + " px");
        }

        ParsedStyleValue ParseStyleFontValue(string property)
        {
            var token = Expect("STRING", "font name string");
            if (string.IsNullOrWhiteSpace(token.Value))
                throw new CompileError("SEMANTIC", "S211", token.Line, token.Column, "Font name cannot be empty.");
            ExpectLine();
            return new ParsedStyleValue("string", token.Value, "", token.Value);
        }

        ParsedStyleValue ParseStyleColorValue(string property)
        {
            if (CurrentIs("LBRACKET") || IsKeyword("color"))
            {
                var start = Current;
                var expr = ParseAddExpression(legacyQuotedStrings: false);
                if (expr.Type == "vec4")
                {
                    var values = ToVector(expr);
                    if (values.Any(v => v < 0 || v > 1))
                        throw new CompileError("SEMANTIC", "S212", start.Line, start.Column, $"Style color vector components must be between 0 and 1.");
                    ExpectLine();
                    return new ParsedStyleValue("vec4", FormatVector(values), "", FormatVector(values));
                }
                if (expr.Type == "color")
                {
                    ExpectLine();
                    return new ParsedStyleValue("color", expr.Value, "", expr.Value);
                }
                throw new CompileError("SEMANTIC", "S212", start.Line, start.Column, $"Style property '{property}' requires a named color, color literal, or vec4.");
            }

            var color = ReadStyleWordsUntilLine(property).ToLowerInvariant();
            if (!StyleColorNames.Contains(color))
                throw new CompileError("SEMANTIC", "S212", Current.Line, Current.Column, $"Unknown style color '{color}'.");
            ExpectLine();
            return new ParsedStyleValue("named_color", color.Replace(" ", "_"), "", color);
        }

        string ReadStyleWordsUntilLine(string property)
        {
            var words = new List<string>();
            while (!CurrentIs("NEWLINE") && !CurrentIs("EOF"))
            {
                if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                    throw new CompileError("PARSE", "P203", Current.Line, Current.Column, $"Expected word value for style property '{property}'.");
                words.Add(Advance().Value);
            }
            if (words.Count == 0)
                throw new CompileError("PARSE", "P203", Current.Line, Current.Column, $"Expected value for style property '{property}'.");
            return string.Join(" ", words);
        }
    }
}
