using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

static partial class Program
{
    sealed partial class Parser
    {
        // M19E/F/G/H UI final foundation: events, bindings, states, and resources.
        // Metadata only. No runtime input dispatch, asset loading, hit testing, layout solving, or rendering here.

        static readonly HashSet<string> UiEventNames = new(StringComparer.Ordinal)
        {
            "clicked",
            "hovered",
            "pressed",
            "released",
            "focused",
            "unfocused",
            "changed",
            "value changed",
            "text changed",
            "dragged",
            "dropped",
            "loaded",
            "resized",
        };

        static readonly HashSet<string> UiButtonLikeEvents = new(StringComparer.Ordinal)
        {
            "clicked",
            "pressed",
            "released",
            "hovered",
            "focused",
            "unfocused",
            "dragged",
            "dropped",
            "loaded",
        };

        static readonly HashSet<string> UiBindingProperties = new(StringComparer.Ordinal)
        {
            "content",
            "width",
            "height",
            "visibility",
            "visible",
            "enabled",
            "checked",
            "selected",
            "value",
            "color",
            "background color",
            "foreground color",
            "border color",
            "opacity",
        };

        static readonly HashSet<string> UiStateProperties = new(StringComparer.Ordinal)
        {
            "enabled",
            "visible",
            "selected",
            "focused",
            "hovered",
            "pressed",
            "loading",
            "visibility",
            "state",
        };

        static readonly HashSet<string> UiStateValues = new(StringComparer.Ordinal)
        {
            "default",
            "visible",
            "hidden",
            "hovered",
            "pressed",
            "disabled",
            "focused",
            "unfocused",
            "active",
            "selected",
            "checked",
            "loading",
            "visited",
            "dragged",
            "dropped",
            "error",
            "warning",
            "success",
        };

        static readonly HashSet<string> UiResourceTypes = new(StringComparer.Ordinal)
        {
            "texture",
            "font",
            "sound",
        };

        static readonly HashSet<string> UiResourceProperties = new(StringComparer.Ordinal)
        {
            "texture",
            "font",
            "sound",
        };

        bool LooksLikeUiStateSet()
            => IsKeyword("set") &&
               (PeekWord("enabled") || PeekWord("visible") || PeekWord("selected") || PeekWord("focused") ||
                PeekWord("hovered") || PeekWord("pressed") || PeekWord("loading") || PeekWord("visibility") ||
                PeekWord("state")) &&
               PeekKeyword("of", 2);

        bool LooksLikeUiResourceDefinition()
            => IsKeyword("define") &&
               (PeekWord("texture") || PeekWord("font") || PeekWord("sound"));

        bool LooksLikeUiResourceUse()
            => IsKeyword("set") &&
               (PeekWord("texture") || PeekWord("font") || PeekWord("sound")) &&
               PeekKeyword("of", 2);

        void ParseUiEventStatementAfterWhen(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI event blocks inside compile-time if are not supported in M19E.");

            var eventTok = Current;
            var eventName = ParseUiEventName();
            var targetTok = Expect("STRING", "UI event target");
            ExpectLine();

            var targetKind = ResolveUiEventTarget(targetTok, eventName);
            ValidateUiEventCompatibility(eventTok, eventName, targetTok.Value, targetKind);

            var eventKey = eventName + "|" + targetTok.Value;
            if (!_uiEventKeys.Add(eventKey))
                throw new CompileError("SEMANTIC", "S252", eventTok.Line, eventTok.Column, $"Duplicate UI event '{eventName}' for '{targetTok.Value}'.");

            var body = ReadUiMetadataBlock("when", "P250", "S253", "UI event block cannot be empty.");
            if (apply)
                _uiEvents.Add(new UiEvent(eventName, targetTok.Value, targetKind, body.Count, body.BodyText));
        }

        string ParseUiEventName()
        {
            if (CurrentWordIs("value") && PeekWord("changed"))
            {
                Advance();
                Advance();
                return "value changed";
            }
            if (CurrentWordIs("text") && PeekWord("changed"))
            {
                Advance();
                Advance();
                return "text changed";
            }

            if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                throw new CompileError("PARSE", "P250", Current.Line, Current.Column, "Expected UI event name after when.");
            var tok = Advance();
            if (!UiEventNames.Contains(tok.Value))
                throw new CompileError("SEMANTIC", "S250", tok.Line, tok.Column, $"Unsupported UI event '{tok.Value}'.");
            return tok.Value;
        }

        string ResolveUiEventTarget(Token targetTok, string eventName)
        {
            if (_uiObjectTypes.ContainsKey(targetTok.Value))
                return "ui";
            if (_definedWindows.Contains(targetTok.Value) && (eventName == "resized" || eventName == "loaded"))
                return "window";
            throw new CompileError("SEMANTIC", "S251", targetTok.Line, targetTok.Column, $"Unknown UI event target '{targetTok.Value}'.");
        }

        void ValidateUiEventCompatibility(Token eventTok, string eventName, string target, string targetKind)
        {
            if (targetKind == "window")
                return;

            var objectType = _uiObjectTypes[target];
            var ok = eventName switch
            {
                "clicked" => objectType is "button" or "checkbox" or "dropdown" or "shape" or "text",
                "value changed" => objectType is "slider" or "checkbox" or "dropdown",
                "text changed" => objectType is "input field" or "text",
                "changed" => objectType is "slider" or "input field" or "checkbox" or "dropdown",
                "resized" => objectType is "shape",
                _ => UiButtonLikeEvents.Contains(eventName),
            };

            if (!ok)
                throw new CompileError("SEMANTIC", "S250", eventTok.Line, eventTok.Column, $"UI event '{eventName}' is not supported on {objectType}.");
        }

        (int Count, string BodyText) ReadUiMetadataBlock(string blockName, string missingEndCode, string emptyCode, string emptyMessage)
        {
            var bodyLineCount = 0;
            var currentLine = -1;
            var bodyText = new System.Text.StringBuilder();

            SkipNewlines();
            while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekWord(blockName)))
            {
                if (IsKeyword("when"))
                    throw new CompileError("SEMANTIC", "S254", Current.Line, Current.Column, "Nested UI event blocks are not supported in M19E.");

                if (!CurrentIs("NEWLINE"))
                {
                    if (Current.Line != currentLine)
                    {
                        currentLine = Current.Line;
                        bodyLineCount++;
                        if (bodyText.Length > 0) bodyText.Append(" ; ");
                    }
                    else if (bodyText.Length > 0)
                    {
                        bodyText.Append(' ');
                    }
                    bodyText.Append(Current.Value);
                }
                Advance();
            }

            if (CurrentIs("EOF"))
                throw new CompileError("PARSE", missingEndCode, Current.Line, Current.Column, $"Expected end {blockName}.");
            if (bodyLineCount == 0)
                throw new CompileError("SEMANTIC", emptyCode, Current.Line, Current.Column, emptyMessage);

            ExpectKeyword("end");
            ExpectWord(blockName, missingEndCode, $"Expected end {blockName}.");
            ExpectLine();
            return (bodyLineCount, bodyText.ToString());
        }

        void ParseUiBindingStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI bindings inside compile-time if are not supported in M19F.");

            ExpectWord("link", "P260", "Expected link statement.");
            var targetTok = Expect("STRING", "UI binding target");
            var propertyTok = Current;
            var property = ReadUiWordsUntilKeyword("to", "P260", "Expected UI binding property.");
            ExpectKeyword("to");
            var sourceTok = Expect("STRING", "binding source symbol");
            ExpectLine();

            ValidateUiChildTarget(targetTok);
            if (!UiBindingProperties.Contains(property))
                throw new CompileError("SEMANTIC", "S260", propertyTok.Line, propertyTok.Column, $"Unsupported UI binding property '{property}'.");
            if (!_vars.TryGetValue(sourceTok.Value, out var sourceInfo))
                throw new CompileError("SEMANTIC", "S261", sourceTok.Line, sourceTok.Column, $"Unknown binding source symbol '{sourceTok.Value}'.");
            ValidateUiBindingType(propertyTok, property, sourceTok.Value, sourceInfo.Type);

            var key = targetTok.Value + "|" + property;
            if (!_uiBindingKeys.Add(key))
                throw new CompileError("SEMANTIC", "S262", targetTok.Line, targetTok.Column, $"Duplicate UI binding for '{targetTok.Value}' property '{property}'.");

            if (apply)
                _uiBindings.Add(new UiBinding(targetTok.Value, property, sourceTok.Value, sourceInfo.Type));
        }

        void ValidateUiBindingType(Token propertyTok, string property, string source, string sourceType)
        {
            var ok = property switch
            {
                "content" => true,
                "width" or "height" or "opacity" or "value" => IsNumeric(sourceType),
                "visibility" or "visible" or "enabled" or "checked" or "selected" => sourceType == "bool",
                "color" or "background color" or "foreground color" or "border color" => sourceType is "color" or "vec4",
                _ => false,
            };
            if (!ok)
                throw new CompileError("SEMANTIC", "S263", propertyTok.Line, propertyTok.Column, $"Binding source '{source}' with type '{sourceType}' is not compatible with UI property '{property}'.");
        }

        void ParseUiStateStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI state statements inside compile-time if are not supported in M19G.");

            ExpectKeyword("set");
            var propertyTok = Current;
            var property = ParseUiStatePropertyName();
            ExpectKeyword("of");
            var targetTok = Expect("STRING", "UI state target");
            ExpectKeyword("to");

            ValidateUiChildTarget(targetTok);
            var parsed = ParseUiStateValue(property, propertyTok);

            var key = targetTok.Value + "|" + property;
            if (!_uiStateKeys.Add(key))
                throw new CompileError("SEMANTIC", "S272", targetTok.Line, targetTok.Column, $"Duplicate UI state '{property}' for '{targetTok.Value}'.");

            if (apply)
                _uiStates.Add(new UiState(targetTok.Value, property, parsed.Kind, parsed.Value));
        }

        string ParseUiStatePropertyName()
        {
            if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                throw new CompileError("PARSE", "P270", Current.Line, Current.Column, "Expected UI state property.");
            var tok = Advance();
            if (!UiStateProperties.Contains(tok.Value))
                throw new CompileError("SEMANTIC", "S270", tok.Line, tok.Column, $"Unsupported UI state property '{tok.Value}'.");
            return tok.Value;
        }

        record ParsedUiStateValue(string Kind, string Value);

        ParsedUiStateValue ParseUiStateValue(string property, Token propertyTok)
        {
            if (property == "state" || property == "visibility")
            {
                var value = ReadUiWordsUntilLine("UI state value", "P270");
                if (!UiStateValues.Contains(value))
                    throw new CompileError("SEMANTIC", "S271", propertyTok.Line, propertyTok.Column, $"Unsupported UI state value '{value}'.");
                ExpectLine();
                return new ParsedUiStateValue("state", value);
            }

            if (!CurrentIs("BOOL"))
                throw new CompileError("SEMANTIC", "S271", Current.Line, Current.Column, $"UI state property '{property}' requires a boolean value.");
            var tok = Advance();
            ExpectLine();
            return new ParsedUiStateValue("bool", tok.Value);
        }

        void ParseUiResourceDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI resource definitions inside compile-time if are not supported in M19H.");

            ExpectKeyword("define");
            var typeTok = ParseUiResourceTypeToken();
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "UI resource name");
            ExpectKeyword("from");
            ExpectKeyword("file");
            var pathTok = Expect("STRING", "UI resource file path");
            ExpectLine();

            ValidateUiResourceDefinition(typeTok, nameTok, pathTok);
            _uiResourceTypes[nameTok.Value] = typeTok.Value;
            if (apply)
                _uiResources.Add(new UiResource(typeTok.Value, nameTok.Value, pathTok.Value));
        }

        Token ParseUiResourceTypeToken()
        {
            if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                throw new CompileError("PARSE", "P280", Current.Line, Current.Column, "Expected UI resource type.");
            var tok = Advance();
            if (!UiResourceTypes.Contains(tok.Value))
                throw new CompileError("SEMANTIC", "S280", tok.Line, tok.Column, $"Unsupported UI resource type '{tok.Value}'.");
            return tok;
        }

        void ValidateUiResourceDefinition(Token typeTok, Token nameTok, Token pathTok)
        {
            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S281", nameTok.Line, nameTok.Column, "UI resource name cannot be empty.");
            if (_uiResourceTypes.ContainsKey(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S281", nameTok.Line, nameTok.Column, $"UI resource '{nameTok.Value}' is already defined.");
            if (string.IsNullOrWhiteSpace(pathTok.Value))
                throw new CompileError("SEMANTIC", "S282", pathTok.Line, pathTok.Column, "UI resource path cannot be empty.");
            if (!UiResourceExtensionAllowed(typeTok.Value, pathTok.Value))
                throw new CompileError("SEMANTIC", "S283", pathTok.Line, pathTok.Column, $"Unsupported {typeTok.Value} resource file extension.");
        }

        static bool UiResourceExtensionAllowed(string type, string path)
        {
            var ext = Path.GetExtension(path).ToLowerInvariant();
            return type switch
            {
                "texture" => ext is ".png" or ".jpg" or ".jpeg" or ".webp" or ".bmp",
                "font" => ext is ".ttf" or ".otf",
                "sound" => ext is ".wav" or ".ogg" or ".mp3",
                _ => false,
            };
        }

        void ParseUiResourceUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "UI resource assignments inside compile-time if are not supported in M19H.");

            ExpectKeyword("set");
            var propertyTok = ParseUiResourcePropertyToken();
            ExpectKeyword("of");
            var targetTok = Expect("STRING", "UI resource assignment target");
            ExpectKeyword("to");
            var resourceTok = Expect("STRING", "UI resource name");
            ExpectLine();

            ValidateUiChildTarget(targetTok);
            if (!_uiResourceTypes.TryGetValue(resourceTok.Value, out var resourceType))
                throw new CompileError("SEMANTIC", "S284", resourceTok.Line, resourceTok.Column, $"Unknown UI resource '{resourceTok.Value}'.");
            if (propertyTok.Value != resourceType)
                throw new CompileError("SEMANTIC", "S285", propertyTok.Line, propertyTok.Column, $"UI resource property '{propertyTok.Value}' requires a {propertyTok.Value} resource.");
            ValidateUiResourceTarget(propertyTok, targetTok.Value, propertyTok.Value);

            var key = targetTok.Value + "|" + propertyTok.Value;
            if (!_uiResourceUseKeys.Add(key))
                throw new CompileError("SEMANTIC", "S286", targetTok.Line, targetTok.Column, $"Duplicate UI resource assignment '{propertyTok.Value}' for '{targetTok.Value}'.");

            if (apply)
                _uiResourceUses.Add(new UiResourceUse(targetTok.Value, propertyTok.Value, resourceTok.Value, resourceType));
        }

        Token ParseUiResourcePropertyToken()
        {
            if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                throw new CompileError("PARSE", "P281", Current.Line, Current.Column, "Expected UI resource property.");
            var tok = Advance();
            if (!UiResourceProperties.Contains(tok.Value))
                throw new CompileError("SEMANTIC", "S280", tok.Line, tok.Column, $"Unsupported UI resource property '{tok.Value}'.");
            return tok;
        }

        void ValidateUiResourceTarget(Token propertyTok, string target, string property)
        {
            var type = _uiObjectTypes[target];
            var ok = property switch
            {
                "texture" => type is "shape" or "button" or "checkbox" or "dropdown",
                "font" => type is "text" or "button" or "input field" or "dropdown",
                "sound" => type is "button" or "checkbox" or "dropdown",
                _ => false,
            };
            if (!ok)
                throw new CompileError("SEMANTIC", "S285", propertyTok.Line, propertyTok.Column, $"UI object type '{type}' does not support {property} resources.");
        }

        string ReadUiWordsUntilKeyword(string stopKeyword, string code, string missingMessage)
        {
            var words = new List<string>();
            while (!CurrentIs("EOF") && !CurrentIs("NEWLINE") && !IsKeyword(stopKeyword))
            {
                if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                    throw new CompileError("PARSE", code, Current.Line, Current.Column, missingMessage);
                words.Add(Advance().Value);
            }
            if (words.Count == 0)
                throw new CompileError("PARSE", code, Current.Line, Current.Column, missingMessage);
            return string.Join(" ", words);
        }

        string ReadUiWordsUntilLine(string what, string code)
        {
            var words = new List<string>();
            while (!CurrentIs("EOF") && !CurrentIs("NEWLINE"))
            {
                if (Current.Type != "KEYWORD" && Current.Type != "IDENT")
                    throw new CompileError("PARSE", code, Current.Line, Current.Column, $"Expected {what}.");
                words.Add(Advance().Value);
            }
            if (words.Count == 0)
                throw new CompileError("PARSE", code, Current.Line, Current.Column, $"Expected {what}.");
            return string.Join(" ", words);
        }
    }
}
