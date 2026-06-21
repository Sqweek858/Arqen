using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: Operations.

        ExprResult ApplyLogical(string op, ExprResult left, ExprResult right)
        {
            if (left.Type != "bool" || right.Type != "bool")
                throw new CompileError("SEMANTIC", "S041", Current.Line, Current.Column, $"{op} requires bool operands.");
            var value = op == "and"
                ? left.Value == "true" && right.Value == "true"
                : left.Value == "true" || right.Value == "true";
            return new ExprResult("bool", value.ToString().ToLowerInvariant(), $"{op}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyPlus(ExprResult left, ExprResult right)
        {
            if (left.Type == "text" && right.Type == "text")
                return new ExprResult("text", left.Value + right.Value, $"plus({left.Repr},{right.Repr})");
            if (IsComplex(left.Type) || IsComplex(right.Type))
                return ApplyComplexBinary("+", left, right);
            if (IsVector(left.Type) || IsVector(right.Type))
                return ApplyVectorBinary("+", left, right);
            if (IsNumeric(left.Type) && IsNumeric(right.Type))
                return ApplyNumericBinary("+", left, right);
            throw new CompileError("SEMANTIC", "S011", Current.Line, Current.Column, "Type mismatch in expression.");
        }

        ExprResult ApplyComplexBinary(string op, ExprResult left, ExprResult right)
        {
            if ((!IsComplex(left.Type) && !IsNumeric(left.Type)) || (!IsComplex(right.Type) && !IsNumeric(right.Type)))
                throw new CompileError("SEMANTIC", "S171", Current.Line, Current.Column, "Complex operation requires complex or numeric operands.");
            var l = ToComplex(left);
            var r = ToComplex(right);
            var result = op switch
            {
                "+" => (R: l.R + r.R, I: l.I + r.I),
                "-" => (R: l.R - r.R, I: l.I - r.I),
                "*" => (R: l.R * r.R - l.I * r.I, I: l.R * r.I + l.I * r.R),
                "/" => ComplexDivide(l, r),
                _ => throw new CompileError("SEMANTIC", "S171", Current.Line, Current.Column, $"Unsupported complex operator {op}."),
            };
            return new ExprResult("complex", FormatComplex(result.R, result.I), $"complex_{op}({left.Repr},{right.Repr})");
        }

        static (double R, double I) ComplexDivide((double R, double I) left, (double R, double I) right)
        {
            var denom = right.R * right.R + right.I * right.I;
            if (Math.Abs(denom) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S172", 0, 0, "Complex division by zero.");
            return ((left.R * right.R + left.I * right.I) / denom, (left.I * right.R - left.R * right.I) / denom);
        }

        ExprResult ApplyVectorBinary(string op, ExprResult left, ExprResult right)
        {
            if (op is "+" or "-")
            {
                if (!IsVector(left.Type) || !IsVector(right.Type) || left.Type != right.Type)
                    throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, $"Vector {op} requires matching vector operands.");
                var l = ToVector(left);
                var r = ToVector(right);
                var result = l.Select((value, index) => op == "+" ? value + r[index] : value - r[index]).ToArray();
                return new ExprResult(left.Type, FormatVector(result), $"{op}({left.Repr},{right.Repr})");
            }

            if (op == "*")
            {
                if (IsVector(left.Type) && IsNumeric(right.Type))
                {
                    var scalar = ToNumber(right);
                    var result = ToVector(left).Select(value => value * scalar).ToArray();
                    return new ExprResult(left.Type, FormatVector(result), $"mul({left.Repr},{right.Repr})");
                }
                if (IsNumeric(left.Type) && IsVector(right.Type))
                {
                    var scalar = ToNumber(left);
                    var result = ToVector(right).Select(value => scalar * value).ToArray();
                    return new ExprResult(right.Type, FormatVector(result), $"mul({left.Repr},{right.Repr})");
                }
            }

            if (op == "/")
            {
                if (!IsVector(left.Type) || !IsNumeric(right.Type))
                    throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, "Vector division requires vector / numeric scalar.");
                var scalar = ToNumber(right);
                if (Math.Abs(scalar) < 0.0000000001)
                    throw new CompileError("SEMANTIC", "S046", Current.Line, Current.Column, "Division by zero.");
                var result = ToVector(left).Select(value => value / scalar).ToArray();
                return new ExprResult(left.Type, FormatVector(result), $"div({left.Repr},{right.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", Current.Line, Current.Column, $"Unsupported vector operator {op}.");
        }

        ExprResult ApplyNumericBinary(string op, ExprResult left, ExprResult right)
        {
            if (IsComplex(left.Type) || IsComplex(right.Type))
                return ApplyComplexBinary(op, left, right);

            if (IsVector(left.Type) || IsVector(right.Type))
                return ApplyVectorBinary(op, left, right);

            if (!IsNumeric(left.Type) || !IsNumeric(right.Type))
                throw new CompileError("SEMANTIC", "S044", Current.Line, Current.Column, "Numeric expression requires numeric operands.");

            if (op == "%" && (left.Type != "int" || right.Type != "int"))
                throw new CompileError("SEMANTIC", "S045", Current.Line, Current.Column, "Modulo only supports integer operands.");

            var l = ToNumber(left);
            var r = ToNumber(right);
            if ((op == "/" || op == "%") && Math.Abs(r) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S046", Current.Line, Current.Column, "Division by zero.");

            var type = op == "%" ? "int" : PromoteNumericType(left.Type, right.Type, op);
            var value = op switch
            {
                "+" => l + r,
                "-" => l - r,
                "*" => l * r,
                "/" => l / r,
                "%" => l % r,
                "^" => Math.Pow(l, r),
                _ => throw new CompileError("SEMANTIC", "S044", Current.Line, Current.Column, "Unknown numeric operator."),
            };

            if (op is "+" or "-" or "*" or "^" && type == "int")
                value = Math.Round(value);
            return new ExprResult(type, FormatNumber(value, type), $"{op}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyScalarUnaryFunction(Token functionTok, ExprResult value)
        {
            var acceptsAngle = functionTok.Value is "sin" or "cos" or "tan";
            if (!IsNumeric(value.Type) && !(acceptsAngle && IsAngle(value.Type)))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a numeric operand." + (acceptsAngle ? " Angle operands are also accepted." : ""));

            var n = ToNumber(value);
            var result = functionTok.Value switch
            {
                "abs" => Math.Abs(n),
                "sqrt" => n < 0 ? throw new CompileError("SEMANTIC", "S091", functionTok.Line, functionTok.Column, "sqrt requires a non-negative operand.") : Math.Sqrt(n),
                "floor" => Math.Floor(n),
                "ceil" => Math.Ceiling(n),
                "round" => Math.Round(n, MidpointRounding.AwayFromZero),
                "trunc" => Math.Truncate(n),
                "sin" => Math.Sin(n),
                "cos" => Math.Cos(n),
                "tan" => Math.Tan(n),
                "asin" => n < -1 || n > 1 ? throw new CompileError("SEMANTIC", "S095", functionTok.Line, functionTok.Column, "asin requires operand between -1 and 1.") : Math.Asin(n),
                "acos" => n < -1 || n > 1 ? throw new CompileError("SEMANTIC", "S095", functionTok.Line, functionTok.Column, "acos requires operand between -1 and 1.") : Math.Acos(n),
                "atan" => Math.Atan(n),
                "sinh" => Math.Sinh(n),
                "cosh" => Math.Cosh(n),
                "tanh" => Math.Tanh(n),
                "asinh" => Math.Asinh(n),
                "acosh" => n < 1 ? throw new CompileError("SEMANTIC", "S095", functionTok.Line, functionTok.Column, "acosh requires operand greater than or equal to 1.") : Math.Acosh(n),
                "atanh" => n <= -1 || n >= 1 ? throw new CompileError("SEMANTIC", "S095", functionTok.Line, functionTok.Column, "atanh requires operand between -1 and 1, exclusive.") : Math.Atanh(n),
                "log" => n <= 0 ? throw new CompileError("SEMANTIC", "S092", functionTok.Line, functionTok.Column, "log requires an operand greater than 0.") : Math.Log(n),
                "log10" => n <= 0 ? throw new CompileError("SEMANTIC", "S092", functionTok.Line, functionTok.Column, "log10 requires an operand greater than 0.") : Math.Log10(n),
                "log2" => n <= 0 ? throw new CompileError("SEMANTIC", "S092", functionTok.Line, functionTok.Column, "log2 requires an operand greater than 0.") : Math.Log2(n),
                "exp" => Math.Exp(n),
                "exp2" => Math.Pow(2, n),
                _ => throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\"."),
            };

            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ApplyScalarBinaryFunction(Token functionTok, ExprResult left, ExprResult right)
        {
            if (!IsNumeric(left.Type) || !IsNumeric(right.Type))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires numeric operands.");

            var l = ToNumber(left);
            var r = ToNumber(right);
            var result = functionTok.Value switch
            {
                "min" => Math.Min(l, r),
                "max" => Math.Max(l, r),
                "pow" => Math.Pow(l, r),
                "atan2" => Math.Atan2(l, r),
                _ => throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\"."),
            };

            var type = PromoteNumericType(left.Type, right.Type, functionTok.Value);
            if (functionTok.Value is "pow" or "atan2")
                type = "double";
            if (type == "int" && Math.Abs(result - Math.Round(result)) > 0.0000000001)
                type = "double";
            return new ExprResult(type, FormatNumber(result, type), $"{functionTok.Value}({left.Repr},{right.Repr})");
        }

        ExprResult ApplyClampFunction(Token functionTok, ExprResult value, ExprResult min, ExprResult max)
        {
            if (!IsNumeric(value.Type) || !IsNumeric(min.Type) || !IsNumeric(max.Type))
                throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, "clamp requires numeric operands.");

            var lo = ToNumber(min);
            var hi = ToNumber(max);
            if (lo > hi)
                throw new CompileError("SEMANTIC", "S093", functionTok.Line, functionTok.Column, "clamp minimum cannot be greater than maximum.");

            var n = ToNumber(value);
            var result = Math.Min(Math.Max(n, lo), hi);
            var type = PromoteNumericType(PromoteNumericType(value.Type, min.Type, "clamp"), max.Type, "clamp");
            if (type == "int" && Math.Abs(result - Math.Round(result)) > 0.0000000001)
                type = "double";
            return new ExprResult(type, FormatNumber(result, type), $"clamp({value.Repr},{min.Repr},{max.Repr})");
        }

        ExprResult ApplyAdvancedScalarUnary(Token functionTok, ExprResult value)
        {
            if (!IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a numeric operand.");
            var n = ToNumber(value);
            var result = functionTok.Value switch
            {
                "saturate" => Math.Min(Math.Max(n, 0), 1),
                "sign" => Math.Sign(n),
                "fract" => n - Math.Floor(n),
                _ => throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"Unknown advanced scalar function \"{functionTok.Value}\"."),
            };
            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ApplyStepFunction(Token functionTok, ExprResult edge, ExprResult value)
        {
            if (!IsNumeric(edge.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "step requires numeric operands.");
            return new ExprResult("double", ToNumber(value) < ToNumber(edge) ? "0" : "1", $"step({edge.Repr},{value.Repr})");
        }

        ExprResult ApplySmoothStepFunction(Token functionTok, ExprResult edge0, ExprResult edge1, ExprResult value, bool smoother)
        {
            if (!IsNumeric(edge0.Type) || !IsNumeric(edge1.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires numeric operands.");
            var lo = ToNumber(edge0);
            var hi = ToNumber(edge1);
            if (IsNearlyZero(hi - lo))
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, $"{functionTok.Value} edges cannot be equal.");
            var t = (ToNumber(value) - lo) / (hi - lo);
            var result = smoother ? SmootherStep01(t) : SmoothStep01(t);
            var repr = smoother ? "smootherstep" : "smoothstep";
            return new ExprResult("double", FormatNumber(result, "double"), $"{repr}({edge0.Repr},{edge1.Repr},{value.Repr})");
        }

        ExprResult ApplyInverseLerpFunction(Token functionTok, ExprResult a, ExprResult b, ExprResult value, bool clamped)
        {
            if (!IsNumeric(a.Type) || !IsNumeric(b.Type) || !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "inverse lerp requires numeric operands.");
            var start = ToNumber(a);
            var end = ToNumber(b);
            if (IsNearlyZero(end - start))
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, "inverse lerp range cannot be zero.");
            var result = (ToNumber(value) - start) / (end - start);
            if (clamped)
                result = Clamp01(result);
            var repr = clamped ? "clamped_inverse_lerp" : "inverse_lerp";
            return new ExprResult("double", FormatNumber(result, "double"), $"{repr}({a.Repr},{b.Repr},{value.Repr})");
        }

        ExprResult ApplyRemapFunction(Token functionTok, ExprResult value, ExprResult inMin, ExprResult inMax, ExprResult outMin, ExprResult outMax, bool clamped)
        {
            if (!IsNumeric(value.Type) || !IsNumeric(inMin.Type) || !IsNumeric(inMax.Type) || !IsNumeric(outMin.Type) || !IsNumeric(outMax.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "remap requires numeric operands.");
            var a = ToNumber(inMin);
            var b = ToNumber(inMax);
            if (IsNearlyZero(b - a))
                throw new CompileError("SEMANTIC", "S121", functionTok.Line, functionTok.Column, "remap input range cannot be zero.");
            var t = (ToNumber(value) - a) / (b - a);
            if (clamped)
                t = Clamp01(t);
            var result = ToNumber(outMin) + (ToNumber(outMax) - ToNumber(outMin)) * t;
            var repr = clamped ? "clamped_remap" : "remap";
            return new ExprResult("double", FormatNumber(result, "double"), $"{repr}({value.Repr},{inMin.Repr},{inMax.Repr},{outMin.Repr},{outMax.Repr})");
        }

        ExprResult ApplyEaseFunction(Token functionTok, string mode, string curve, ExprResult value)
        {
            if (!IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S125", functionTok.Line, functionTok.Column, "ease requires a numeric factor.");

            var t = ToNumber(value);
            if (t < -NumericEpsilon || t > 1 + NumericEpsilon)
                throw new CompileError("SEMANTIC", "S125", functionTok.Line, functionTok.Column, "ease factor must be between 0 and 1.");
            t = Clamp01(t);

            var result = curve switch
            {
                "linear" => t,
                "sine" => mode switch
                {
                    "in" => 1 - Math.Cos(t * Math.PI / 2),
                    "out" => Math.Sin(t * Math.PI / 2),
                    "in out" => -(Math.Cos(Math.PI * t) - 1) / 2,
                    _ => throw new CompileError("SEMANTIC", "S125", functionTok.Line, functionTok.Column, "Unknown ease direction."),
                },
                "quad" => EasePolynomial(mode, t, 2),
                "cubic" => EasePolynomial(mode, t, 3),
                "quart" => EasePolynomial(mode, t, 4),
                "quint" => EasePolynomial(mode, t, 5),
                _ => throw new CompileError("SEMANTIC", "S125", functionTok.Line, functionTok.Column, $"Unknown ease curve \"{curve}\"."),
            };

            return new ExprResult("double", FormatNumber(result, "double"), $"ease_{mode.Replace(" ", "_")}_{curve}({value.Repr})");
        }

        static double EasePolynomial(string mode, double t, int power)
            => mode switch
            {
                "in" => Math.Pow(t, power),
                "out" => 1 - Math.Pow(1 - t, power),
                "in out" => t < 0.5
                    ? Math.Pow(2, power - 1) * Math.Pow(t, power)
                    : 1 - Math.Pow(-2 * t + 2, power) / 2,
                _ => throw new CompileError("SEMANTIC", "S125", 0, 0, "Unknown ease direction."),
            };

        ExprResult ApplyLerpFunction(Token functionTok, ExprResult a, ExprResult b, ExprResult t)
        {
            if (!IsNumeric(t.Type))
                throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, "lerp factor must be numeric.");
            var factor = ToNumber(t);
            if (IsNumeric(a.Type) && IsNumeric(b.Type))
            {
                var result = ToNumber(a) + (ToNumber(b) - ToNumber(a)) * factor;
                return new ExprResult("double", FormatNumber(result, "double"), $"lerp({a.Repr},{b.Repr},{t.Repr})");
            }
            if (IsVector(a.Type) && IsVector(b.Type) && a.Type == b.Type)
            {
                var av = ToVector(a);
                var bv = ToVector(b);
                var result = av.Select((component, index) => component + (bv[index] - component) * factor).ToArray();
                return new ExprResult(a.Type, FormatVector(result), $"lerp({a.Repr},{b.Repr},{t.Repr})");
            }
            throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "lerp requires matching numeric or vector endpoints.");
        }

        ExprResult ApplyDistanceFunction(Token functionTok, ExprResult a, ExprResult b)
        {
            if (!IsVector(a.Type) || !IsVector(b.Type) || a.Type != b.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "distance requires matching vector operands.");
            var av = ToVector(a);
            var bv = ToVector(b);
            var result = Math.Sqrt(av.Select((component, index) => component - bv[index]).Sum(delta => delta * delta));
            return new ExprResult("double", FormatNumber(result, "double"), $"distance({a.Repr},{b.Repr})");
        }

        ExprResult ApplyReflectFunction(Token functionTok, ExprResult dir, ExprResult normal)
        {
            if (!IsVector(dir.Type) || !IsVector(normal.Type) || dir.Type != normal.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "reflect requires matching vector operands.");
            var d = ToVector(dir);
            var n = ToVector(normal);
            var dot = d.Select((component, index) => component * n[index]).Sum();
            var result = d.Select((component, index) => component - 2 * dot * n[index]).ToArray();
            return new ExprResult(dir.Type, FormatVector(result), $"reflect({dir.Repr},{normal.Repr})");
        }

        ExprResult ApplyProjectFunction(Token functionTok, ExprResult value, ExprResult onto)
        {
            if (!IsVector(value.Type) || !IsVector(onto.Type) || value.Type != onto.Type)
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "project requires matching vector operands.");
            var v = ToVector(value);
            var o = ToVector(onto);
            var denom = o.Sum(component => component * component);
            if (Math.Abs(denom) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S123", functionTok.Line, functionTok.Column, "project target vector cannot be zero.");
            var scale = v.Select((component, index) => component * o[index]).Sum() / denom;
            var result = o.Select(component => component * scale).ToArray();
            return new ExprResult(value.Type, FormatVector(result), $"project({value.Repr},{onto.Repr})");
        }

        ExprResult ApplyClampLengthFunction(Token functionTok, ExprResult value, ExprResult max)
        {
            if (!IsVector(value.Type) || !IsNumeric(max.Type))
                throw new CompileError("SEMANTIC", "S122", functionTok.Line, functionTok.Column, "clamp length requires vector and numeric max length.");
            var limit = ToNumber(max);
            if (limit < 0)
                throw new CompileError("SEMANTIC", "S124", functionTok.Line, functionTok.Column, "clamp length max cannot be negative.");
            var vector = ToVector(value);
            var len = Math.Sqrt(vector.Sum(component => component * component));
            if (len <= limit || Math.Abs(len) < 0.0000000001)
                return value;
            var result = vector.Select(component => component / len * limit).ToArray();
            return new ExprResult(value.Type, FormatVector(result), $"clamp_length({value.Repr},{max.Repr})");
        }

        static long ToInt64Strict(ExprResult expr, Token token, string code, string label)
        {
            if (expr.Type != "int")
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, $"{label} requires int operand.");
            return long.Parse(expr.Value, CultureInfo.InvariantCulture);
        }

        ExprResult ApplyComponentFunction(Token functionTok, bool legacyQuotedStrings)
        {
            if (!CurrentWordIs("sum") && !CurrentWordIs("average") && !CurrentWordIs("min") && !CurrentWordIs("max") && !CurrentWordIs("product"))
                throw new CompileError("PARSE", "P210", Current.Line, Current.Column, "Expected component sum, average, min, max, or product.");
            var mode = Advance().Value;
            var value = ParseUnaryExpression(legacyQuotedStrings);
            if (!IsVector(value.Type))
                throw new CompileError("SEMANTIC", "S210", functionTok.Line, functionTok.Column, "component aggregate requires vector operand.");
            var v = ToVector(value);
            var result = mode switch
            {
                "sum" => v.Sum(),
                "average" => v.Average(),
                "min" => v.Min(),
                "max" => v.Max(),
                "product" => v.Aggregate(1.0, (a, b) => a * b),
                _ => throw new CompileError("SEMANTIC", "S210", functionTok.Line, functionTok.Column, "Unknown component aggregate.")
            };
            return new ExprResult("double", FormatNumber(result, "double"), $"component_{mode}({value.Repr})");
        }

        ExprResult ApplyBitFunction(Token functionTok, bool legacyQuotedStrings)
        {
            if (!CurrentWordIs("and") && !CurrentWordIs("or") && !CurrentWordIs("xor") && !CurrentWordIs("not"))
                throw new CompileError("PARSE", "P211", Current.Line, Current.Column, "Expected bit and, bit or, bit xor, or bit not.");
            var op = Advance().Value;
            var left = ParseAddExpression(legacyQuotedStrings);
            var l = ToInt64Strict(left, functionTok, "S211", "bit " + op);
            long result;
            if (op == "not")
            {
                result = ~l;
            }
            else
            {
                Expect("COMMA", "comma between bit operands");
                var right = ParseAddExpression(legacyQuotedStrings);
                var r = ToInt64Strict(right, functionTok, "S211", "bit " + op);
                result = op switch
                {
                    "and" => l & r,
                    "or" => l | r,
                    "xor" => l ^ r,
                    _ => throw new CompileError("SEMANTIC", "S211", functionTok.Line, functionTok.Column, "Unknown bit operation.")
                };
            }
            return new ExprResult("int", result.ToString(CultureInfo.InvariantCulture), $"bit_{op}({left.Repr})");
        }

        ExprResult ApplyShiftFunction(Token functionTok, bool legacyQuotedStrings)
        {
            if (!CurrentWordIs("left") && !CurrentWordIs("right"))
                throw new CompileError("PARSE", "P212", Current.Line, Current.Column, "Expected shift left or shift right.");
            var dir = Advance().Value;
            var value = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("by", "P213", "Expected by in shift expression.");
            var amount = ParseAddExpression(legacyQuotedStrings);
            var v = ToInt64Strict(value, functionTok, "S212", "shift");
            var bits = ToInt64Strict(amount, functionTok, "S212", "shift amount");
            if (bits < 0 || bits > 62)
                throw new CompileError("SEMANTIC", "S212", functionTok.Line, functionTok.Column, "shift amount must be between 0 and 62.");
            var result = dir == "left" ? v << (int)bits : v >> (int)bits;
            return new ExprResult("int", result.ToString(CultureInfo.InvariantCulture), $"shift_{dir}({value.Repr},{amount.Repr})");
        }

        ExprResult ApplyGeometryDistance(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("from", "P214", "Expected from after distance.");
            ExpectWord("point", "P215", "Expected point after distance from.");
            var point = ParseAddExpression(legacyQuotedStrings);
            if (point.Type != "vec2")
                throw new CompileError("SEMANTIC", "S213", functionTok.Line, functionTok.Column, "distance from point requires vec2 point.");
            ExpectWord("to", "P216", "Expected to in geometry distance expression.");
            if (!CurrentWordIs("line") && !CurrentWordIs("segment"))
                throw new CompileError("PARSE", "P217", Current.Line, Current.Column, "Expected line or segment in geometry distance expression.");
            var targetKind = Advance().Value;
            var target = ParseAddExpression(legacyQuotedStrings);
            var p = ToVector(point);
            double result;
            if (targetKind == "line")
            {
                if (target.Type != "line")
                    throw new CompileError("SEMANTIC", "S213", functionTok.Line, functionTok.Column, "distance to line requires line operand.");
                result = DistancePointToLine(p, ToSegment(target));
            }
            else
            {
                if (target.Type != "segment")
                    throw new CompileError("SEMANTIC", "S213", functionTok.Line, functionTok.Column, "distance to segment requires segment operand.");
                var closest = ClosestPointOnSegment(ToSegment(target), p);
                result = Math.Sqrt(DistanceSquared(closest, p));
            }
            return new ExprResult("double", FormatNumber(result, "double"), $"distance_point_{targetKind}({point.Repr},{target.Repr})");
        }

        ExprResult ApplyBezierFunction(Token functionTok, string degree, bool legacyQuotedStrings)
        {
            ExpectWord("bezier", "P220", "Expected bezier after quadratic/cubic.");
            if (!CurrentWordIs("point") && !CurrentWordIs("tangent"))
                throw new CompileError("PARSE", "P221", Current.Line, Current.Column, "Expected point or tangent after bezier.");
            var mode = Advance().Value;
            var p0 = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between bezier points");
            var p1 = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between bezier points");
            var p2 = ParseAddExpression(legacyQuotedStrings);
            ExprResult? p3 = null;
            if (degree == "cubic")
            {
                Expect("COMMA", "comma between bezier points");
                p3 = ParseAddExpression(legacyQuotedStrings);
            }
            ExpectWord("at", "P222", "Expected at in bezier expression.");
            var tExpr = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(tExpr.Type))
                throw new CompileError("SEMANTIC", "S220", functionTok.Line, functionTok.Column, "bezier t must be numeric.");
            var t = ToNumber(tExpr);
            if (t < -NumericEpsilon || t > 1 + NumericEpsilon)
                throw new CompileError("SEMANTIC", "S220", functionTok.Line, functionTok.Column, "bezier t must be between 0 and 1.");
            return degree == "quadratic"
                ? ApplyQuadraticBezier(functionTok, mode, p0, p1, p2, Clamp01(t))
                : ApplyCubicBezier(functionTok, mode, p0, p1, p2, p3!, Clamp01(t));
        }

        ExprResult ApplyCatmullFunction(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("point", "P223", "Expected point after catmull.");
            var p0 = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between catmull points");
            var p1 = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between catmull points");
            var p2 = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between catmull points");
            var p3 = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("at", "P224", "Expected at in catmull expression.");
            var tExpr = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(tExpr.Type))
                throw new CompileError("SEMANTIC", "S221", functionTok.Line, functionTok.Column, "catmull t must be numeric.");
            var t = ToNumber(tExpr);
            if (t < -NumericEpsilon || t > 1 + NumericEpsilon)
                throw new CompileError("SEMANTIC", "S221", functionTok.Line, functionTok.Column, "catmull t must be between 0 and 1.");
            ValidateCurveVectors(functionTok, p0, p1, p2, p3);
            var a = ToVector(p0);
            var b = ToVector(p1);
            var c = ToVector(p2);
            var d = ToVector(p3);
            var t2 = t * t;
            var t3 = t2 * t;
            var result = a.Select((_, i) => 0.5 * ((2 * b[i]) + (-a[i] + c[i]) * t + (2 * a[i] - 5 * b[i] + 4 * c[i] - d[i]) * t2 + (-a[i] + 3 * b[i] - 3 * c[i] + d[i]) * t3)).ToArray();
            return new ExprResult(p0.Type, FormatVector(result), $"catmull({p0.Repr},{p1.Repr},{p2.Repr},{p3.Repr})");
        }

        static void ValidateCurveVectors(Token token, params ExprResult[] points)
        {
            if (points.Any(p => !IsVector(p.Type)) || points.Any(p => p.Type != points[0].Type))
                throw new CompileError("SEMANTIC", "S220", token.Line, token.Column, "curve points must be matching vectors.");
        }

        ExprResult ApplyQuadraticBezier(Token token, string mode, ExprResult p0, ExprResult p1, ExprResult p2, double t)
        {
            ValidateCurveVectors(token, p0, p1, p2);
            var a = ToVector(p0);
            var b = ToVector(p1);
            var c = ToVector(p2);
            double[] result = mode == "point"
                ? a.Select((_, i) => (1 - t) * (1 - t) * a[i] + 2 * (1 - t) * t * b[i] + t * t * c[i]).ToArray()
                : a.Select((_, i) => 2 * (1 - t) * (b[i] - a[i]) + 2 * t * (c[i] - b[i])).ToArray();
            return new ExprResult(p0.Type, FormatVector(result), $"quadratic_bezier_{mode}({p0.Repr},{p1.Repr},{p2.Repr})");
        }

        ExprResult ApplyCubicBezier(Token token, string mode, ExprResult p0, ExprResult p1, ExprResult p2, ExprResult p3, double t)
        {
            ValidateCurveVectors(token, p0, p1, p2, p3);
            var a = ToVector(p0);
            var b = ToVector(p1);
            var c = ToVector(p2);
            var d = ToVector(p3);
            var u = 1 - t;
            double[] result = mode == "point"
                ? a.Select((_, i) => u * u * u * a[i] + 3 * u * u * t * b[i] + 3 * u * t * t * c[i] + t * t * t * d[i]).ToArray()
                : a.Select((_, i) => 3 * u * u * (b[i] - a[i]) + 6 * u * t * (c[i] - b[i]) + 3 * t * t * (d[i] - c[i])).ToArray();
            return new ExprResult(p0.Type, FormatVector(result), $"cubic_bezier_{mode}({p0.Repr},{p1.Repr},{p2.Repr},{p3.Repr})");
        }

    }
}
