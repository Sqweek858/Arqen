using System;
using System.Collections.Generic;
using System.Globalization;

static partial class Program
{
    sealed partial class Parser
    {
        // M19D UI hierarchy/layout foundation.

        static readonly HashSet<string> UiLayoutProperties = new(StringComparer.Ordinal)
        {
            "x",
            "y",
            "width",
            "height",
            "anchor",
            "offset x",
            "offset y",
            "margin",
            "padding",
            "mode",
            "direction",
            "gap",
            "columns",
            "rows",
        };

        static readonly HashSet<string> UiLayoutAnchorValues = new(StringComparer.Ordinal)
        {
            "center",
            "top",
            "bottom",
            "left",
            "right",
            "top left",
            "top right",
            "bottom left",
            "bottom right",
        };

        static readonly HashSet<string> UiLayoutModeValues = new(StringComparer.Ordinal)
        {
            "absolute",
            "flex",
            "grid",
        };

        static readonly HashSet<string> UiLayoutDirectionValues = new(StringComparer.Ordinal)
        {
            "horizontal",
            "vertical",
        };

        static readonly HashSet<string> UiDockSideValues = new(StringComparer.Ordinal)
        {
            "top",
            "right",
            "bottom",
            "left",
            "fill",
            "center",
        };

        void ParseUiParentStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI parent statements inside compile-time if are not supported in M19D.");

            ExpectWord("parent", "P240", "Expected parent statement.");
            var childTok = Expect("STRING", "UI child name");
            ExpectKeyword("to");
            var parentTok = Expect("STRING", "UI parent name");
            ExpectLine();

            ValidateUiChildTarget(childTok);
            ValidateUiParentTarget(parentTok);

            if (childTok.Value == parentTok.Value)
                throw new CompileError("SEMANTIC", "S246", childTok.Line, childTok.Column, "UI object cannot be parented to itself.");
            if (_uiParentByChild.ContainsKey(childTok.Value) || _uiDockTargets.Contains(childTok.Value))
                throw new CompileError("SEMANTIC", "S248", childTok.Line, childTok.Column, $"UI object '{childTok.Value}' already has a parent or dock relationship.");
            if (WouldCreateParentCycle(childTok.Value, parentTok.Value))
                throw new CompileError("SEMANTIC", "S246", childTok.Line, childTok.Column, "UI parent relationship would create a cycle.");

            _uiParentByChild[childTok.Value] = parentTok.Value;
            if (apply)
                _uiParents.Add(new UiParent(childTok.Value, parentTok.Value));
        }

        void ParseUiDockStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI dock statements inside compile-time if are not supported in M19D.");

            ExpectWord("dock", "P240", "Expected dock statement.");
            var targetTok = Expect("STRING", "UI dock target name");
            ExpectKeyword("to");
            var sideTok = ExpectLayoutWord("dock side");
            ExpectKeyword("of");
            var parentTok = Expect("STRING", "dock parent name");
            ExpectLine();

            ValidateUiChildTarget(targetTok);
            ValidateUiParentTarget(parentTok);

            if (!UiDockSideValues.Contains(sideTok.Value))
                throw new CompileError("SEMANTIC", "S247", sideTok.Line, sideTok.Column, $"Unsupported dock side '{sideTok.Value}'.");
            if (targetTok.Value == parentTok.Value)
                throw new CompileError("SEMANTIC", "S246", targetTok.Line, targetTok.Column, "UI object cannot be docked to itself.");
            if (_uiDockTargets.Contains(targetTok.Value) || _uiParentByChild.ContainsKey(targetTok.Value))
                throw new CompileError("SEMANTIC", "S248", targetTok.Line, targetTok.Column, $"UI object '{targetTok.Value}' already has a parent or dock relationship.");
            if (WouldCreateParentCycle(targetTok.Value, parentTok.Value))
                throw new CompileError("SEMANTIC", "S246", targetTok.Line, targetTok.Column, "UI dock relationship would create a cycle.");

            _uiDockTargets.Add(targetTok.Value);
            if (apply)
                _uiDocks.Add(new UiDock(targetTok.Value, sideTok.Value, parentTok.Value));
        }

        void ParseUiLayoutStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI layout blocks inside compile-time if are not supported in M19D.");

            ExpectKeyword("with");
            ExpectWord("layout", "P240", "Expected layout keyword.");
            ExpectKeyword("for");
            var targetTok = Expect("STRING", "layout target name");
            ExpectLine();

            ValidateUiChildTarget(targetTok);

            var count = 0;
            SkipNewlines();
            while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekWord("layout")))
            {
                var propertyTok = Current;
                var property = ParseUiLayoutPropertyName();
                Expect("COLON", "colon after layout property");
                var value = ParseUiLayoutValue(property, propertyTok);

                var key = targetTok.Value + "|" + property;
                if (!_uiLayoutPropertyKeys.Add(key))
                    throw new CompileError("SEMANTIC", "S242", propertyTok.Line, propertyTok.Column, $"Duplicate layout property '{property}' for '{targetTok.Value}'.");

                count++;
                if (apply)
                    _uiLayoutProperties.Add(new UiLayoutProperty(targetTok.Value, property, value.Kind, value.Value, value.Unit, value.Source));

                SkipNewlines();
            }

            if (CurrentIs("EOF"))
                throw new CompileError("PARSE", "P240", targetTok.Line, targetTok.Column, "Expected end layout.");
            if (count == 0)
                throw new CompileError("SEMANTIC", "S243", targetTok.Line, targetTok.Column, $"Layout block for '{targetTok.Value}' cannot be empty.");

            ExpectKeyword("end");
            ExpectWord("layout", "P240", "Expected end layout.");
            ExpectLine();
        }

        string ParseUiLayoutPropertyName()
        {
            if (CurrentWordIs("x")) { Advance(); return "x"; }
            if (CurrentWordIs("y")) { Advance(); return "y"; }
            if (CurrentWordIs("width")) { Advance(); return "width"; }
            if (CurrentWordIs("height")) { Advance(); return "height"; }
            if (CurrentWordIs("anchor")) { Advance(); return "anchor"; }
            if (CurrentWordIs("margin")) { Advance(); return "margin"; }
            if (CurrentWordIs("padding")) { Advance(); return "padding"; }
            if (CurrentWordIs("mode")) { Advance(); return "mode"; }
            if (CurrentWordIs("direction")) { Advance(); return "direction"; }
            if (CurrentWordIs("gap")) { Advance(); return "gap"; }
            if (CurrentWordIs("columns")) { Advance(); return "columns"; }
            if (CurrentWordIs("rows")) { Advance(); return "rows"; }
            if (CurrentWordIs("offset"))
            {
                Advance();
                if (CurrentWordIs("x")) { Advance(); return "offset x"; }
                if (CurrentWordIs("y")) { Advance(); return "offset y"; }
                throw new CompileError("PARSE", "P240", Current.Line, Current.Column, "Expected x or y after offset.");
            }
            throw new CompileError("SEMANTIC", "S241", Current.Line, Current.Column, "Unknown layout property.");
        }

        record ParsedUiLayoutValue(string Kind, string Value, string Unit, string Source);

        ParsedUiLayoutValue ParseUiLayoutValue(string property, Token propertyTok)
        {
            return property switch
            {
                "x" or "y" or "offset x" or "offset y" => ParseUiLayoutSignedDimensionValue(property),
                "width" or "height" or "margin" or "padding" or "gap" => ParseUiLayoutDimensionValue(property),
                "anchor" => ParseUiLayoutEnumValue(property, UiLayoutAnchorValues),
                "mode" => ParseUiLayoutEnumValue(property, UiLayoutModeValues),
                "direction" => ParseUiLayoutEnumValue(property, UiLayoutDirectionValues),
                "columns" or "rows" => ParseUiLayoutTrackCountValue(property),
                _ => throw new CompileError("SEMANTIC", "S241", propertyTok.Line, propertyTok.Column, $"Unknown layout property '{property}'."),
            };
        }

        ParsedUiLayoutValue ParseUiLayoutEnumValue(string property, HashSet<string> allowed)
        {
            var start = Current;
            var value = ReadUiLayoutWordsUntilLine(property).ToLowerInvariant();
            if (!allowed.Contains(value))
                throw new CompileError("SEMANTIC", "S243", start.Line, start.Column, $"Unsupported {property} value '{value}'.");
            ExpectLine();
            return new ParsedUiLayoutValue("enum", value, "", value);
        }

        ParsedUiLayoutValue ParseUiLayoutDimensionValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S243", start.Line, start.Column, $"Layout property '{property}' requires a numeric px value.");
            var value = ToNumber(expr);
            if (value < 0)
                throw new CompileError("SEMANTIC", "S243", start.Line, start.Column, $"Layout property '{property}' cannot be negative.");
            if (!CurrentWordIs("px"))
                throw new CompileError("PARSE", "P240", Current.Line, Current.Column, $"Expected px unit for layout property '{property}'.");
            Advance();
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedUiLayoutValue("dimension", formatted, "px", formatted + " px");
        }

        ParsedUiLayoutValue ParseUiLayoutSignedDimensionValue(string property)
        {
            var start = Current;
            var sign = 1.0;
            var signText = "";
            if (CurrentIs("MINUS") || CurrentIs("PLUS"))
            {
                signText = Current.Value;
                sign = CurrentIs("MINUS") ? -1.0 : 1.0;
                Advance();
            }
            if (!CurrentIs("INT") && !CurrentIs("DECIMAL"))
                throw new CompileError("SEMANTIC", "S243", start.Line, start.Column, $"Layout property '{property}' requires a signed numeric px value.");
            var numberTok = Advance();
            if (!double.TryParse(numberTok.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var rawValue))
                throw new CompileError("SEMANTIC", "S243", numberTok.Line, numberTok.Column, $"Layout property '{property}' requires a signed numeric px value.");
            var value = sign * rawValue;
            if (!CurrentWordIs("px"))
                throw new CompileError("PARSE", "P240", Current.Line, Current.Column, $"Expected px unit for layout property '{property}'.");
            Advance();
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedUiLayoutValue("dimension", formatted, "px", signText + numberTok.Value + " px");
        }

        ParsedUiLayoutValue ParseUiLayoutTrackCountValue(string property)
        {
            var start = Current;
            if (CurrentWordIs("auto"))
            {
                Advance();
                ExpectLine();
                return new ParsedUiLayoutValue("track", "auto", "", "auto");
            }
            if (!CurrentIs("INT"))
                throw new CompileError("SEMANTIC", "S243", start.Line, start.Column, $"Layout property '{property}' requires a positive integer or auto.");
            var tok = Advance();
            ExpectLine();
            if (!int.TryParse(tok.Value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var value) || value <= 0)
                throw new CompileError("SEMANTIC", "S243", tok.Line, tok.Column, $"Layout property '{property}' requires a positive integer or auto.");
            return new ParsedUiLayoutValue("track", value.ToString(CultureInfo.InvariantCulture), "", tok.Value);
        }

        string ReadUiLayoutWordsUntilLine(string context)
        {
            var words = new List<string>();
            while (!CurrentIs("NEWLINE") && !CurrentIs("EOF"))
            {
                if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                    throw new CompileError("PARSE", "P240", Current.Line, Current.Column, $"Expected word value for layout property '{context}'.");
                words.Add(Advance().Value);
            }
            if (words.Count == 0)
                throw new CompileError("PARSE", "P240", Current.Line, Current.Column, $"Expected value for layout property '{context}'.");
            return string.Join(" ", words);
        }

        Token ExpectLayoutWord(string what)
        {
            if (Current.Type == "KEYWORD" || Current.Type == "IDENT")
                return Advance();
            throw new CompileError("PARSE", "P240", Current.Line, Current.Column, $"Expected {what}.");
        }

        void ValidateUiChildTarget(Token targetTok)
        {
            if (!_uiObjectTypes.ContainsKey(targetTok.Value))
                throw new CompileError("SEMANTIC", "S240", targetTok.Line, targetTok.Column, $"Unknown UI object '{targetTok.Value}'.");
        }

        void ValidateUiParentTarget(Token parentTok)
        {
            if (!_uiObjectTypes.ContainsKey(parentTok.Value) && !_definedWindows.Contains(parentTok.Value))
                throw new CompileError("SEMANTIC", "S245", parentTok.Line, parentTok.Column, $"Unknown UI parent target '{parentTok.Value}'.");
        }

        bool WouldCreateParentCycle(string child, string parent)
        {
            var cursor = parent;
            var guard = 0;
            while (_uiParentByChild.TryGetValue(cursor, out var next))
            {
                if (next == child)
                    return true;
                cursor = next;
                guard++;
                if (guard > 1024)
                    return true;
            }
            return false;
        }
    }
}
