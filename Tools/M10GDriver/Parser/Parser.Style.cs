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

        static readonly HashSet<string> StyleProperties = new(StringComparer.Ordinal)
        {
            "type",
            "display",
            "color",
            "background color",
            "foreground color",
            "accent color",
            "border color",
            "border size",
            "outline color",
            "outline size",
            "corner radius",
            "padding",
            "margin",
            "opacity",
            "visibility",
            "clip children",
            "font",
            "size",
            "font weight",
            "font style",
            "text align",
            "vertical align",
            "line height",
            "letter spacing",
            "wrap",
            "shadow color",
            "shadow opacity",
            "shadow blur",
            "shadow spread",
            "shadow offset x",
            "shadow offset y",
            "cursor",
            "transition duration",
            "transition easing",
            "blend mode",
            "z index",
            "min width",
            "min height",
            "max width",
            "max height",
            "preferred width",
            "preferred height",
            "aspect ratio",
            "overflow",
            "pointer events",
            "interactable",
            "scale",
            "scale x",
            "scale y",
            "rotation",
            "translate x",
            "translate y",
            "pivot",
            "transition property",
            "transition delay",
            "animation duration",
            "animation easing",
            "title bar color",
            "title text color",
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
            "circle",
            "ellipse",
            "icon",
            "progress bar",
            "scrollbar",
        };

        static readonly HashSet<string> StyleColorNames = new(StringComparer.Ordinal)
        {
            "black",
            "white",
            "red",
            "green",
            "blue",
            "transparent",
            "gray",
            "grey",
            "dark gray",
            "dark grey",
            "light gray",
            "light grey",
            "yellow",
            "orange",
            "purple",
            "pink",
            "cyan",
            "magenta",
            "lime",
            "teal",
            "navy",
            "brown",
            "silver",
            "gold",
            "violet",
            "indigo",
            "crimson",
            "emerald",
            "amber",
            "slate",
            "light blue",
            "dark blue",
        };

        static readonly HashSet<string> StyleDisplayValues = new(StringComparer.Ordinal)
        {
            "block",
            "inline",
            "flex",
            "grid",
            "none",
        };

        static readonly HashSet<string> StyleFontWeightWords = new(StringComparer.Ordinal)
        {
            "thin",
            "light",
            "normal",
            "medium",
            "semibold",
            "bold",
            "black",
        };

        static readonly HashSet<string> StyleFontStyleValues = new(StringComparer.Ordinal)
        {
            "normal",
            "italic",
            "oblique",
        };

        static readonly HashSet<string> StyleTextAlignValues = new(StringComparer.Ordinal)
        {
            "left",
            "center",
            "right",
            "justify",
        };

        static readonly HashSet<string> StyleVerticalAlignValues = new(StringComparer.Ordinal)
        {
            "top",
            "middle",
            "bottom",
            "baseline",
        };

        static readonly HashSet<string> StyleCursorValues = new(StringComparer.Ordinal)
        {
            "default",
            "pointer",
            "text",
            "move",
            "resize",
            "none",
        };

        static readonly HashSet<string> StyleTransitionEasingValues = new(StringComparer.Ordinal)
        {
            "linear",
            "smooth",
            "ease in",
            "ease out",
            "ease in out",
            "bounce",
        };

        static readonly HashSet<string> StyleBlendModeValues = new(StringComparer.Ordinal)
        {
            "normal",
            "alpha",
            "additive",
            "multiply",
            "screen",
            "overlay",
            "subtract",
        };

        static readonly HashSet<string> StyleOverflowValues = new(StringComparer.Ordinal)
        {
            "visible",
            "hidden",
            "scroll",
            "auto",
        };

        static readonly HashSet<string> StylePivotValues = new(StringComparer.Ordinal)
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

        static readonly HashSet<string> StyleTransitionPropertyValues = new(StringComparer.Ordinal)
        {
            "all",
            "color",
            "background color",
            "foreground color",
            "opacity",
            "transform",
            "border",
            "outline",
            "shadow",
            "scale",
            "position",
        };

        void ParseStylePresetStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "style preset blocks inside compile-time if are not supported in M19B++.");

            ExpectKeyword("define");
            ExpectKeyword("style");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "style preset name");
            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S213", nameTok.Line, nameTok.Column, "Style preset name cannot be empty.");
            if (_stylePresetNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S213", nameTok.Line, nameTok.Column, $"Duplicate style preset '{nameTok.Value}'.");
            _stylePresetNames.Add(nameTok.Value);
            ExpectLine();

            var seenProperties = new HashSet<string>(StringComparer.Ordinal);
            var count = ParseStylePropertyBlock(
                owner: nameTok.Value,
                state: "preset",
                endKeyword: "style",
                seenProperties: seenProperties,
                onProperty: parsed =>
                {
                    if (apply)
                        _stylePresets.Add(new StylePresetProperty(nameTok.Value, parsed.Property, parsed.Value.Kind, parsed.Value.Value, parsed.Value.Unit, parsed.Value.Source));
                });

            if (count == 0)
                throw new CompileError("SEMANTIC", "S215", nameTok.Line, nameTok.Column, $"Style preset '{nameTok.Value}' cannot be empty.");
        }

        void ParseUseStyleStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "style application inside compile-time if is not supported in M19B++.");

            ExpectKeyword("use");
            ExpectKeyword("style");
            var styleTok = Expect("STRING", "style preset name");
            ExpectKeyword("for");
            var targetTok = Expect("STRING", "style target name");
            var state = "default";

            if (IsKeyword("when"))
            {
                ExpectKeyword("when");
                var stateTok = ExpectStyleWord("style application state");
                state = stateTok.Value;
                if (!StyleStates.Contains(state))
                    throw new CompileError("SEMANTIC", "S201", stateTok.Line, stateTok.Column, $"Unsupported style state '{state}'.");
            }

            ExpectLine();

            if (!_stylePresetNames.Contains(styleTok.Value))
                throw new CompileError("SEMANTIC", "S214", styleTok.Line, styleTok.Column, $"Unknown style preset '{styleTok.Value}'.");

            var applyKey = styleTok.Value + "|" + targetTok.Value + "|" + state;
            if (!_styleApplications.Add(applyKey))
                throw new CompileError("SEMANTIC", "S216", styleTok.Line, styleTok.Column, $"Duplicate style application '{styleTok.Value}' for '{targetTok.Value}' state '{state}'.");

            RegisterDx12RendererStylePresetApplication(styleTok, targetTok, state, apply);
            RegisterNativeWindowStylePresetApplication(styleTok, targetTok, state, apply);

            if (apply)
                _styleApplies.Add(new StyleApplication(styleTok.Value, targetTok.Value, state));
        }

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

            ValidateDx12RendererStyleState(targetTok, state);

            var blockKey = targetTok.Value + "|" + state;
            if (_styleBlocks.Contains(blockKey))
                throw new CompileError("SEMANTIC", "S202", targetTok.Line, targetTok.Column, $"Duplicate style block for '{targetTok.Value}' state '{state}'.");
            _styleBlocks.Add(blockKey);

            var seenProperties = new HashSet<string>(StringComparer.Ordinal);
            var count = ParseStylePropertyBlock(
                owner: targetTok.Value,
                state: state,
                endKeyword: "style",
                seenProperties: seenProperties,
                onProperty: parsed =>
                {
                    RegisterDx12RendererStyleProperty(targetTok, state, parsed, apply);
                    RegisterNativeWindowStyleProperty(targetTok, state, parsed, apply);
                    if (apply)
                        _styles.Add(new StyleProperty(targetTok.Value, state, parsed.Property, parsed.Value.Kind, parsed.Value.Value, parsed.Value.Unit, parsed.Value.Source));
                });

            if (count == 0)
                throw new CompileError("SEMANTIC", "S205", targetTok.Line, targetTok.Column, $"Style block for '{targetTok.Value}' cannot be empty.");
        }

        void ValidateDx12RendererStyleState(Token targetTok, string state)
        {
            if (!_dx12RendererNames.Contains(targetTok.Value))
                return;
            if (state != "default")
                throw new CompileError("SEMANTIC", "S265", targetTok.Line, targetTok.Column, "DX12 renderer styles only support the default state in M20C.");
        }


        void ValidateNativeWindowStyleState(Token targetTok, string state)
        {
            if (!_definedWindows.Contains(targetTok.Value))
                return;
            if (state != "default")
                throw new CompileError("SEMANTIC", "S371", targetTok.Line, targetTok.Column, "Native window styles only support the default state in M27D.");
        }

        bool IsNativeWindowStyleProperty(string property)
            => property == "title bar color" || property == "title text color";

        void RegisterNativeWindowStyleProperty(Token targetTok, string state, ParsedStyleProperty parsed, bool apply)
        {
            if (!IsNativeWindowStyleProperty(parsed.Property))
                return;
            if (!_definedWindows.Contains(targetTok.Value))
                throw new CompileError("SEMANTIC", "S370", targetTok.Line, targetTok.Column, $"Native window style property '{parsed.Property}' can only target a defined window.");
            ValidateNativeWindowStyleState(targetTok, state);
            if (parsed.Value.Kind != "color")
                throw new CompileError("SEMANTIC", "S372", targetTok.Line, targetTok.Column, $"Native window style property '{parsed.Property}' requires a #RRGGBB color literal.");
            if (apply)
            {
                var op = parsed.Property == "title bar color" ? "window_style_title_bar_color" : "window_style_title_text_color";
                AddRuntimeAction(new RuntimeAction(op, "", parsed.Value.Kind, parsed.Value.Value, targetTok.Value));
            }
        }

        void RegisterNativeWindowStylePresetApplication(Token styleTok, Token targetTok, string state, bool apply)
        {
            if (!_definedWindows.Contains(targetTok.Value))
                return;
            ValidateNativeWindowStyleState(targetTok, state);

            var presetProperties = _stylePresets.Where(p => p.Name == styleTok.Value).ToList();
            foreach (var prop in presetProperties)
            {
                if (!IsNativeWindowStyleProperty(prop.Property))
                    throw new CompileError("SEMANTIC", "S370", styleTok.Line, styleTok.Column, $"Native window style preset '{styleTok.Value}' contains unsupported property '{prop.Property}'.");
                if (prop.ValueKind != "color")
                    throw new CompileError("SEMANTIC", "S372", styleTok.Line, styleTok.Column, $"Native window style property '{prop.Property}' requires a #RRGGBB color literal.");
            }

            foreach (var prop in presetProperties)
            {
                if (!apply)
                    continue;
                var op = prop.Property == "title bar color" ? "window_style_title_bar_color" : "window_style_title_text_color";
                AddRuntimeAction(new RuntimeAction(op, "", prop.ValueKind, prop.Value, targetTok.Value));
            }
        }

        void RegisterDx12RendererStyleProperty(Token targetTok, string state, ParsedStyleProperty parsed, bool apply)
        {
            if (!_dx12RendererNames.Contains(targetTok.Value))
                return;
            ValidateDx12RendererStyleState(targetTok, state);
            if (parsed.Property != "background color")
                throw new CompileError("SEMANTIC", "S266", targetTok.Line, targetTok.Column, $"DX12 renderer style supports only background color in M20C, not '{parsed.Property}'.");
            if (apply)
                AddDx12RendererClearStyle(targetTok, state, parsed.Value.Kind, parsed.Value.Value, parsed.Value.Unit, "style.background_color");
        }

        void RegisterDx12RendererStylePresetApplication(Token styleTok, Token targetTok, string state, bool apply)
        {
            if (!_dx12RendererNames.Contains(targetTok.Value))
                return;
            ValidateDx12RendererStyleState(targetTok, state);

            var presetProperties = _stylePresets.Where(p => p.Name == styleTok.Value).ToList();
            foreach (var prop in presetProperties)
            {
                if (prop.Property != "background color")
                    throw new CompileError("SEMANTIC", "S266", styleTok.Line, styleTok.Column, $"DX12 renderer style preset '{styleTok.Value}' contains unsupported property '{prop.Property}'.");
            }

            var background = presetProperties.FirstOrDefault(p => p.Property == "background color");
            if (background != null && apply)
                AddDx12RendererClearStyle(targetTok, state, background.ValueKind, background.Value, background.Unit, $"style_preset.{styleTok.Value}.background_color");
        }

        void AddDx12RendererClearStyle(Token targetTok, string state, string valueKind, string value, string unit, string source)
        {
            var key = targetTok.Value + "|" + state;
            if (!_dx12RendererClearStyleKeys.Add(key))
                throw new CompileError("SEMANTIC", "S267", targetTok.Line, targetTok.Column, $"DX12 renderer '{targetTok.Value}' already has a default background color style.");
            _dx12RendererClearStyles.Add(new Dx12RendererClearStyle(targetTok.Value, state, valueKind, value, unit, source));
        }

        record ParsedStyleProperty(string Property, ParsedStyleValue Value);

        int ParseStylePropertyBlock(string owner, string state, string endKeyword, HashSet<string> seenProperties, Action<ParsedStyleProperty> onProperty)
        {
            var count = 0;
            SkipNewlines();
            while (!CurrentIs("EOF") && !(IsKeyword("end") && PeekKeyword(endKeyword)))
            {
                var propertyTok = Current;
                var property = ParseStylePropertyName();
                if (!StyleProperties.Contains(property))
                    throw new CompileError("SEMANTIC", "S203", propertyTok.Line, propertyTok.Column, $"Unknown style property '{property}'.");
                if (!seenProperties.Add(property))
                    throw new CompileError("SEMANTIC", "S204", propertyTok.Line, propertyTok.Column, $"Duplicate style property '{property}'.");

                var parsedValue = ParseStylePropertyValue(property, propertyTok);
                onProperty(new ParsedStyleProperty(property, parsedValue));
                count++;
                SkipNewlines();
            }

            if (!IsKeyword("end") || !PeekKeyword(endKeyword))
                throw new CompileError("PARSE", "P200", Current.Line, Current.Column, $"Expected end {endKeyword}.");
            ExpectKeyword("end");
            ExpectKeyword(endKeyword);
            ExpectLine();
            return count;
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
                "display" => ParseStyleEnumValue(property, StyleDisplayValues, "S206"),
                "visibility" => ParseStyleEnumValue(property, new HashSet<string>(StringComparer.Ordinal) { "visible", "hidden", "collapsed" }, "S207"),
                "clip children" => ParseStyleBoolValue(property),
                "wrap" => ParseStyleBoolValue(property),
                "pointer events" => ParseStyleBoolValue(property),
                "interactable" => ParseStyleBoolValue(property),
                "opacity" => ParseStyleOpacityValue(property),
                "shadow opacity" => ParseStyleOpacityValue(property),
                "font" => ParseStyleFontValue(property),
                "font weight" => ParseStyleFontWeightValue(property),
                "font style" => ParseStyleEnumValue(property, StyleFontStyleValues, "S206"),
                "text align" => ParseStyleEnumValue(property, StyleTextAlignValues, "S206"),
                "vertical align" => ParseStyleEnumValue(property, StyleVerticalAlignValues, "S206"),
                "cursor" => ParseStyleEnumValue(property, StyleCursorValues, "S206"),
                "transition easing" => ParseStyleEnumValue(property, StyleTransitionEasingValues, "S206"),
                "animation easing" => ParseStyleEnumValue(property, StyleTransitionEasingValues, "S206"),
                "blend mode" => ParseStyleEnumValue(property, StyleBlendModeValues, "S206"),
                "overflow" => ParseStyleEnumValue(property, StyleOverflowValues, "S206"),
                "pivot" => ParseStyleEnumValue(property, StylePivotValues, "S206"),
                "transition property" => ParseStyleEnumValue(property, StyleTransitionPropertyValues, "S206"),
                "size" => ParseStyleDimensionValue(property),
                "border size" => ParseStyleDimensionValue(property),
                "outline size" => ParseStyleDimensionValue(property),
                "corner radius" => ParseStyleDimensionValue(property),
                "padding" => ParseStyleDimensionValue(property),
                "margin" => ParseStyleDimensionValue(property),
                "line height" => ParseStyleDimensionValue(property),
                "letter spacing" => ParseStyleDimensionValue(property),
                "shadow blur" => ParseStyleDimensionValue(property),
                "shadow spread" => ParseStyleDimensionValue(property),
                "shadow offset x" => ParseStyleDimensionValue(property),
                "shadow offset y" => ParseStyleDimensionValue(property),
                "min width" => ParseStyleDimensionValue(property),
                "min height" => ParseStyleDimensionValue(property),
                "max width" => ParseStyleDimensionValue(property),
                "max height" => ParseStyleDimensionValue(property),
                "preferred width" => ParseStyleDimensionValue(property),
                "preferred height" => ParseStyleDimensionValue(property),
                "translate x" => ParseStyleSignedDimensionValue(property),
                "translate y" => ParseStyleSignedDimensionValue(property),
                "transition duration" => ParseStyleDurationValue(property),
                "transition delay" => ParseStyleDurationValue(property),
                "animation duration" => ParseStyleDurationValue(property),
                "z index" => ParseStyleIntegerValue(property),
                "scale" => ParseStyleNonNegativeNumberValue(property),
                "scale x" => ParseStyleNonNegativeNumberValue(property),
                "scale y" => ParseStyleNonNegativeNumberValue(property),
                "aspect ratio" => ParseStylePositiveNumberValue(property),
                "rotation" => ParseStyleAngleValue(property),
                "color" or "background color" or "foreground color" or "accent color" or "border color" or "outline color" or "shadow color" or "title bar color" or "title text color" => ParseStyleColorValue(property),
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

        ParsedStyleValue ParseStyleSignedDimensionValue(string property)
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
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a signed numeric px value.");

            var numberTok = Advance();
            if (!double.TryParse(numberTok.Value, NumberStyles.Float, CultureInfo.InvariantCulture, out var rawValue))
                throw new CompileError("SEMANTIC", "S210", numberTok.Line, numberTok.Column, $"Style property '{property}' requires a signed numeric px value.");

            var value = sign * rawValue;

            if (!CurrentWordIs("px"))
                throw new CompileError("PARSE", "P204", Current.Line, Current.Column, $"Expected px unit for style property '{property}'.");
            Advance();
            ExpectLine();

            var formatted = FormatNumber(value, "double");
            var source = signText + numberTok.Value + " px";
            return new ParsedStyleValue("dimension", formatted, "px", source);
        }

        ParsedStyleValue ParseStyleNonNegativeNumberValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a numeric value.");
            var value = ToNumber(expr);
            if (value < 0)
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' cannot be negative.");
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedStyleValue("number", formatted, "", expr.Value);
        }

        ParsedStyleValue ParseStylePositiveNumberValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a numeric value.");
            var value = ToNumber(expr);
            if (value <= 0)
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' must be positive.");
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedStyleValue("number", formatted, "", expr.Value);
        }

        ParsedStyleValue ParseStyleAngleValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);

            if (IsAngle(expr.Type))
            {
                ExpectLine();
                var angleValue = ToNumber(expr);
                var formattedAngle = FormatNumber(angleValue, "double");
                return new ParsedStyleValue("angle", formattedAngle, "rad", expr.Repr);
            }

            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a numeric angle value.");

            var value = ToNumber(expr);
            if (!CurrentWordIs("deg") && !CurrentWordIs("rad"))
                throw new CompileError("PARSE", "P204", Current.Line, Current.Column, $"Expected deg or rad unit for style property '{property}'.");
            var unit = Advance().Value;
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedStyleValue("angle", formatted, unit, formatted + " " + unit);
        }

        ParsedStyleValue ParseStyleFontValue(string property)
        {
            var token = Expect("STRING", "font name string");
            if (string.IsNullOrWhiteSpace(token.Value))
                throw new CompileError("SEMANTIC", "S211", token.Line, token.Column, "Font name cannot be empty.");
            ExpectLine();
            return new ParsedStyleValue("string", token.Value, "", token.Value);
        }

        ParsedStyleValue ParseStyleFontWeightValue(string property)
        {
            var start = Current;
            if (CurrentIs("INT"))
            {
                var raw = Advance().Value;
                if (!int.TryParse(raw, NumberStyles.None, CultureInfo.InvariantCulture, out var weight) ||
                    weight < 100 || weight > 900 || weight % 100 != 0)
                    throw new CompileError("SEMANTIC", "S206", start.Line, start.Column, "Font weight must be a word or a numeric weight between 100 and 900 in steps of 100.");
                ExpectLine();
                return new ParsedStyleValue("font_weight", weight.ToString(CultureInfo.InvariantCulture), "", raw);
            }

            var value = ReadStyleWordsUntilLine(property);
            var normalized = value.ToLowerInvariant();
            if (!StyleFontWeightWords.Contains(normalized))
                throw new CompileError("SEMANTIC", "S206", start.Line, start.Column, $"Unsupported font weight '{value}'.");
            ExpectLine();
            return new ParsedStyleValue("font_weight", normalized, "", value);
        }

        ParsedStyleValue ParseStyleDurationValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a numeric duration value.");
            var value = ToNumber(expr);
            if (value < 0)
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' cannot be negative.");
            if (!CurrentWordIs("ms") && !CurrentWordIs("sec"))
                throw new CompileError("PARSE", "P204", Current.Line, Current.Column, $"Expected ms or sec unit for style property '{property}'.");
            var unit = Advance().Value;
            ExpectLine();
            var formatted = FormatNumber(value, "double");
            return new ParsedStyleValue("duration", formatted, unit, formatted + " " + unit);
        }

        ParsedStyleValue ParseStyleIntegerValue(string property)
        {
            var start = Current;
            var expr = ParseAddExpression(legacyQuotedStrings: false);
            if (!IsNumeric(expr.Type))
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires an integer value.");
            var value = ToNumber(expr);
            if (value < 0 || Math.Abs(value - Math.Round(value)) > NumericEpsilon)
                throw new CompileError("SEMANTIC", "S210", start.Line, start.Column, $"Style property '{property}' requires a non-negative integer value.");
            ExpectLine();
            var integer = ((long)Math.Round(value)).ToString(CultureInfo.InvariantCulture);
            return new ParsedStyleValue("integer", integer, "", expr.Value);
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
