using System;
using System.Collections.Generic;
using System.Globalization;

static partial class Program
{
    sealed partial class Parser
    {
        // M19C UI objects basic contract.

        static readonly HashSet<string> UiObjectTypes = new(StringComparer.Ordinal)
        {
            "shape",
            "text",
            "button",
            "slider",
            "input field",
            "checkbox",
            "dropdown",
        };

        static readonly HashSet<string> UiTextContentTypes = new(StringComparer.Ordinal)
        {
            "text",
            "button",
            "checkbox",
            "dropdown",
        };

        bool LooksLikeUiObjectDefinition()
            => IsKeyword("define") &&
               (PeekWord("shape") || PeekWord("text") || PeekWord("button") || PeekWord("slider") ||
                PeekWord("checkbox") || PeekWord("dropdown") || PeekWord("input"));

        bool LooksLikeUiPropertySet()
            => IsKeyword("set") &&
               (PeekWord("content") || PeekWord("range") || PeekWord("value") || PeekWord("placeholder") || PeekWord("checked")) &&
               PeekKeyword("of", 2);

        bool LooksLikeUiDropdownOption()
        {
            if (!IsKeyword("add") || !PeekKeyword("string"))
                return false;

            // Dropdown options use: add string "Option" to "Dropdown".
            // File append uses:      add string "Text" to file "path".
            // Missing "to" file I/O invalid samples must continue through the
            // add/math update parser so they keep the canonical P076 diagnostic.
            for (var i = _pos + 1; i + 1 < _tokens.Count; i++)
            {
                if (_tokens[i].Type is "NEWLINE" or "EOF")
                    return false;

                if (_tokens[i].Type == "KEYWORD" && _tokens[i].Value == "to")
                    return _tokens[i + 1].Type == "STRING";
            }

            return false;
        }

        void ParseUiObjectDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI object definitions inside compile-time if are not supported in M19C.");

            ExpectKeyword("define");
            var type = ParseUiObjectType();
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "UI object name");
            ExpectLine();

            ValidateNewUiObjectName(nameTok);
            _uiObjectTypes[nameTok.Value] = type;
            if (apply)
                _uiObjects.Add(new UiObject(type, nameTok.Value));
        }

        string ParseUiObjectType()
        {
            if (CurrentWordIs("input"))
            {
                ExpectWord("input", "P230", "Expected UI object type.");
                ExpectWord("field", "P230", "Expected input field.");
                return "input field";
            }

            var typeTok = Current;
            if ((typeTok.Type != "KEYWORD" && typeTok.Type != "IDENT") || !UiObjectTypes.Contains(typeTok.Value))
                throw new CompileError("PARSE", "P230", typeTok.Line, typeTok.Column, "Expected UI object type.");
            Advance();
            return typeTok.Value;
        }

        void ValidateNewUiObjectName(Token nameTok)
        {
            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S230", nameTok.Line, nameTok.Column, "UI object name cannot be empty.");
            if (_uiObjectTypes.ContainsKey(nameTok.Value) || SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S230", nameTok.Line, nameTok.Column, $"UI object '{nameTok.Value}' is already defined.");
        }

        void ParseUiPropertySetStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI property sets inside compile-time if are not supported in M19C.");

            ExpectKeyword("set");
            var propertyTok = Current;
            var property = ParseUiPropertyName();
            ExpectKeyword("of");
            var targetTok = Expect("STRING", "UI object name");
            ExpectKeyword("to");

            var objectType = ResolveUiObject(targetTok);
            var value = ParseUiPropertyValue(property, propertyTok, objectType);
            var key = targetTok.Value + "|" + property;
            if (!_uiPropertyKeys.Add(key))
                throw new CompileError("SEMANTIC", "S236", propertyTok.Line, propertyTok.Column, $"Duplicate UI property '{property}' for '{targetTok.Value}'.");

            if (apply)
                _uiProperties.Add(new UiProperty(targetTok.Value, property, value.Kind, value.Value, value.Source));
        }

        string ParseUiPropertyName()
        {
            if (CurrentWordIs("content"))
            {
                ExpectWord("content", "P231", "Expected UI property name.");
                return "content";
            }
            if (CurrentWordIs("range"))
            {
                ExpectWord("range", "P231", "Expected UI property name.");
                return "range";
            }
            if (CurrentWordIs("value"))
            {
                ExpectWord("value", "P231", "Expected UI property name.");
                return "value";
            }
            if (CurrentWordIs("placeholder"))
            {
                ExpectWord("placeholder", "P231", "Expected UI property name.");
                return "placeholder";
            }
            if (CurrentWordIs("checked"))
            {
                ExpectWord("checked", "P231", "Expected UI property name.");
                return "checked";
            }
            throw new CompileError("PARSE", "P231", Current.Line, Current.Column, "Expected UI property name.");
        }

        string ResolveUiObject(Token targetTok)
        {
            if (_uiObjectTypes.TryGetValue(targetTok.Value, out var objectType))
                return objectType;
            throw new CompileError("SEMANTIC", "S231", targetTok.Line, targetTok.Column, $"Unknown UI object '{targetTok.Value}'.");
        }

        record ParsedUiValue(string Kind, string Value, string Source);

        ParsedUiValue ParseUiPropertyValue(string property, Token propertyTok, string objectType)
        {
            return property switch
            {
                "content" => ParseUiContentValue(propertyTok, objectType),
                "placeholder" => ParseUiPlaceholderValue(propertyTok, objectType),
                "range" => ParseUiRangeValue(propertyTok, objectType),
                "value" => ParseUiValueValue(propertyTok, objectType),
                "checked" => ParseUiCheckedValue(propertyTok, objectType),
                _ => throw new CompileError("SEMANTIC", "S232", propertyTok.Line, propertyTok.Column, $"Unsupported UI property '{property}'."),
            };
        }

        ParsedUiValue ParseUiContentValue(Token propertyTok, string objectType)
        {
            if (!UiTextContentTypes.Contains(objectType))
                throw new CompileError("SEMANTIC", "S233", propertyTok.Line, propertyTok.Column, $"UI object type '{objectType}' does not support content.");
            var expr = ParseTextLikeExpression("set content", "P232", "Expected content value.");
            ExpectLine();
            return new ParsedUiValue("text", expr.Value, expr.Repr);
        }

        ParsedUiValue ParseUiPlaceholderValue(Token propertyTok, string objectType)
        {
            if (objectType != "input field")
                throw new CompileError("SEMANTIC", "S233", propertyTok.Line, propertyTok.Column, "placeholder is only supported on input field.");
            var expr = ParseTextLikeExpression("set placeholder", "P233", "Expected placeholder value.");
            ExpectLine();
            return new ParsedUiValue("text", expr.Value, expr.Repr);
        }

        ParsedUiValue ParseUiRangeValue(Token propertyTok, string objectType)
        {
            if (objectType != "slider")
                throw new CompileError("SEMANTIC", "S233", propertyTok.Line, propertyTok.Column, "range is only supported on slider.");
            var minTok = Current;
            var min = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(min.Type))
                throw new CompileError("SEMANTIC", "S234", minTok.Line, minTok.Column, "Slider range minimum must be numeric.");
            Expect("COMMA", "comma between range minimum and maximum");
            var maxTok = Current;
            var max = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(max.Type))
                throw new CompileError("SEMANTIC", "S234", maxTok.Line, maxTok.Column, "Slider range maximum must be numeric.");
            ExpectLine();

            var minValue = ToNumber(min);
            var maxValue = ToNumber(max);
            if (minValue > maxValue)
                throw new CompileError("SEMANTIC", "S235", propertyTok.Line, propertyTok.Column, "Slider range minimum cannot be greater than maximum.");
            return new ParsedUiValue("range", FormatNumber(minValue, "double") + "," + FormatNumber(maxValue, "double"), min.Repr + "," + max.Repr);
        }

        ParsedUiValue ParseUiValueValue(Token propertyTok, string objectType)
        {
            if (objectType == "slider")
            {
                var valueTok = Current;
                var value = ParseAddExpression(legacyQuotedStrings: false);
                if (!IsNumeric(value.Type))
                    throw new CompileError("SEMANTIC", "S234", valueTok.Line, valueTok.Column, "Slider value must be numeric.");
                ExpectLine();
                return new ParsedUiValue("number", FormatNumber(ToNumber(value), "double"), value.Repr);
            }

            if (objectType == "input field")
            {
                var expr = ParseTextLikeExpression("set value", "P234", "Expected input field value.");
                ExpectLine();
                return new ParsedUiValue("text", expr.Value, expr.Repr);
            }

            throw new CompileError("SEMANTIC", "S233", propertyTok.Line, propertyTok.Column, $"UI object type '{objectType}' does not support value.");
        }

        ParsedUiValue ParseUiCheckedValue(Token propertyTok, string objectType)
        {
            if (objectType != "checkbox")
                throw new CompileError("SEMANTIC", "S233", propertyTok.Line, propertyTok.Column, "checked is only supported on checkbox.");
            var token = Current;
            if (!CurrentIs("BOOL"))
                throw new CompileError("SEMANTIC", "S237", token.Line, token.Column, "checked requires a boolean value.");
            Advance();
            ExpectLine();
            return new ParsedUiValue("bool", token.Value, token.Value);
        }

        void ParseUiDropdownOptionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI dropdown options inside compile-time if are not supported in M19C.");

            ExpectKeyword("add");
            var value = ParseCanonicalStringLiteral();
            ExpectKeyword("to");
            var targetTok = Expect("STRING", "dropdown name");
            ExpectLine();

            var objectType = ResolveUiObject(targetTok);
            if (objectType != "dropdown")
                throw new CompileError("SEMANTIC", "S233", targetTok.Line, targetTok.Column, "Dropdown options can only be added to dropdown objects.");

            var key = targetTok.Value + "|option|" + value.Value;
            if (!_uiOptionKeys.Add(key))
                throw new CompileError("SEMANTIC", "S238", targetTok.Line, targetTok.Column, $"Duplicate dropdown option '{value.Value}' for '{targetTok.Value}'.");

            if (apply)
                _uiProperties.Add(new UiProperty(targetTok.Value, "option", "text", value.Value, value.Repr));
        }
    }
}
