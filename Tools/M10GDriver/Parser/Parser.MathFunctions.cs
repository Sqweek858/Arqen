using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: MathFunctions.

        ExprResult ApplyMatrixFunction(Token functionTok)
        {
            var name = functionTok.Value;
            if (name == "translate")
            {
                var v = ParseUnaryExpression(false);
                if (v.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S131", functionTok.Line, functionTok.Column, "translate requires vec3 operand.");
                return new ExprResult("mat4", FormatMatrix(TranslationMatrix(ToVector(v))), $"translate({v.Repr})");
            }
            if (name == "scale")
            {
                var v = ParseUnaryExpression(false);
                if (v.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S131", functionTok.Line, functionTok.Column, "scale requires vec3 operand.");
                return new ExprResult("mat4", FormatMatrix(ScaleMatrix(ToVector(v))), $"scale({v.Repr})");
            }
            if (name == "rotate")
            {
                if (!CurrentWordIs("x") && !CurrentWordIs("y") && !CurrentWordIs("z"))
                    throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "rotate axis must be x, y, or z.");
                var axis = Advance().Value;
                var angle = ParseUnaryExpression(false);
                if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                    throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "rotate angle must be numeric or angle.");
                return new ExprResult("mat4", FormatMatrix(RotationMatrix(axis, ToNumber(angle))), $"rotate({axis},{angle.Repr})");
            }
            if (name == "matmul")
            {
                var left = ParseAddExpression(false);
                Expect("COMMA", "comma between matmul arguments");
                var right = ParseAddExpression(false);
                if (!IsMatrixType(left.Type) || !IsMatrixType(right.Type))
                    throw new CompileError("SEMANTIC", "S130", functionTok.Line, functionTok.Column, "matmul requires matrix or transform operands.");
                return new ExprResult("mat4", FormatMatrix(MultiplyMatrix(ToMatrix(left), ToMatrix(right))), $"matmul({left.Repr},{right.Repr})");
            }
            throw new CompileError("SEMANTIC", "S130", functionTok.Line, functionTok.Column, $"Unknown matrix function \"{name}\".");
        }

        ExprResult ApplyTransformFunction(Token functionTok)
        {
            if (CurrentWordIs("point") || CurrentWordIs("direction"))
            {
                var isPoint = Current.Value == "point";
                Advance();
                var matrix = ParseAddExpression(false);
                Expect("COMMA", "comma between transform arguments");
                var value = ParseAddExpression(false);
                if (!IsMatrixType(matrix.Type))
                    throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "transform point/direction requires mat4 or transform operand.");
                if (value.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "transform point/direction value must be vec3.");
                var result = TransformVector(ToMatrix(matrix), ToVector(value), isPoint);
                return new ExprResult("vec3", FormatVector(result), $"transform_{(isPoint ? "point" : "direction")}({matrix.Repr},{value.Repr})");
            }
            throw new CompileError("SEMANTIC", "S133", functionTok.Line, functionTok.Column, "Expected point or direction after transform.");
        }

        ExprResult ApplyComposeTransform(Token functionTok)
        {
            ExpectWord("transform", "P150", "Expected transform after compose.");
            ExpectWord("position", "P151", "Expected position in compose transform.");
            var position = ParseAddExpression(false);
            ExpectWord("rotation", "P152", "Expected rotation in compose transform.");
            if (!CurrentWordIs("x") && !CurrentWordIs("y") && !CurrentWordIs("z"))
                throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "compose transform rotation axis must be x, y, or z.");
            var axis = Advance().Value;
            var angle = ParseUnaryExpression(false);
            ExpectWord("scale", "P153", "Expected scale in compose transform.");
            var scale = ParseAddExpression(false);
            if (position.Type != "vec3" || scale.Type != "vec3")
                throw new CompileError("SEMANTIC", "S134", functionTok.Line, functionTok.Column, "compose transform requires vec3 position and vec3 scale.");
            if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                throw new CompileError("SEMANTIC", "S132", functionTok.Line, functionTok.Column, "compose transform rotation angle must be numeric or angle.");
            var matrix = MultiplyMatrix(MultiplyMatrix(TranslationMatrix(ToVector(position)), RotationMatrix(axis, ToNumber(angle))), ScaleMatrix(ToVector(scale)));
            return new ExprResult("transform", FormatMatrix(matrix), $"compose_transform({position.Repr},{axis},{angle.Repr},{scale.Repr})");
        }

        ExprResult ApplyRandomFunction(Token functionTok, bool legacyQuotedStrings)
        {
            if (CurrentWordIs("between"))
            {
                Advance();
                var min = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between random range values");
                var max = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(min.Type) || !IsNumeric(max.Type))
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random between requires numeric range values.");
                var lo = ToNumber(min);
                var hi = ToNumber(max);
                EnsureFinite(lo, functionTok, "S180", "random minimum must be finite.");
                EnsureFinite(hi, functionTok, "S180", "random maximum must be finite.");
                if (lo > hi)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random minimum cannot be greater than maximum.");
                var result = LerpDouble(lo, hi, NextRandomUnit());
                return new ExprResult("double", FormatNumber(result, "double"), $"random_between({min.Repr},{max.Repr})");
            }

            if (CurrentWordIs("int"))
            {
                Advance();
                ExpectWord("between", "P182", "Expected between after random int.");
                var min = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between random int range values");
                var max = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(min.Type) || !IsNumeric(max.Type))
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random int between requires numeric range values.");
                var lo = ToNumber(min);
                var hi = ToNumber(max);
                EnsureFinite(lo, functionTok, "S180", "random int minimum must be finite.");
                EnsureFinite(hi, functionTok, "S180", "random int maximum must be finite.");
                if (Math.Abs(lo - Math.Round(lo)) > NumericEpsilon || Math.Abs(hi - Math.Round(hi)) > NumericEpsilon)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random int range values must be integers.");
                var imin = (int)Math.Round(lo);
                var imax = (int)Math.Round(hi);
                if (imin > imax)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random int minimum cannot be greater than maximum.");
                var span = (long)imax - imin + 1L;
                if (span <= 0)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random int range is too large.");
                var result = imin + (int)Math.Min(span - 1, Math.Floor(NextRandomUnit() * span));
                return new ExprResult("int", result.ToString(CultureInfo.InvariantCulture), $"random_int({min.Repr},{max.Repr})");
            }

            if (CurrentWordIs("vector2") || CurrentWordIs("vec2"))
            {
                Advance();
                ExpectWord("inside", "P183", "Expected inside after random vector2.");
                ExpectWord("circle", "P184", "Expected circle after random vector2 inside.");
                ExpectWord("radius", "P185", "Expected radius after random vector2 inside circle.");
                var radius = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(radius.Type))
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random vector2 radius must be numeric.");
                var r = ToNumber(radius);
                EnsureFinite(r, functionTok, "S180", "random vector2 radius must be finite.");
                if (r < 0)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random vector2 radius cannot be negative.");
                var sampleRadius = r * Math.Sqrt(NextRandomUnit());
                var theta = NextRandomUnit() * Math.PI * 2.0;
                var result = new[] { Math.Cos(theta) * sampleRadius, Math.Sin(theta) * sampleRadius };
                return new ExprResult("vec2", FormatVector(result), $"random_vec2_circle({radius.Repr})");
            }

            if (CurrentWordIs("vector3") || CurrentWordIs("vec3"))
            {
                Advance();
                ExpectWord("inside", "P186", "Expected inside after random vector3.");
                ExpectWord("sphere", "P187", "Expected sphere after random vector3 inside.");
                ExpectWord("radius", "P188", "Expected radius after random vector3 inside sphere.");
                var radius = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(radius.Type))
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random vector3 radius must be numeric.");
                var r = ToNumber(radius);
                EnsureFinite(r, functionTok, "S180", "random vector3 radius must be finite.");
                if (r < 0)
                    throw new CompileError("SEMANTIC", "S180", functionTok.Line, functionTok.Column, "random vector3 radius cannot be negative.");
                var u = NextRandomUnit();
                var v = NextRandomUnit();
                var w = NextRandomUnit();
                var theta = 2.0 * Math.PI * u;
                var z = 2.0 * v - 1.0;
                var radial = r * Math.Pow(w, 1.0 / 3.0);
                var xy = Math.Sqrt(Math.Max(0, 1.0 - z * z));
                var result = new[] { radial * xy * Math.Cos(theta), radial * xy * Math.Sin(theta), radial * z };
                return new ExprResult("vec3", FormatVector(result), $"random_vec3_sphere({radius.Repr})");
            }

            throw new CompileError("PARSE", "P182", Current.Line, Current.Column, "Expected between, int, vector2, or vector3 after random.");
        }

        ExprResult ApplyNoiseFunction(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("at", "P189", "Expected at after noise.");
            var point = ParseAddExpression(legacyQuotedStrings);
            uint seed = 0;
            if (CurrentWordIs("seed"))
            {
                Advance();
                var seedExpr = ParseAddExpression(legacyQuotedStrings);
                if (!IsNumeric(seedExpr.Type))
                    throw new CompileError("SEMANTIC", "S181", functionTok.Line, functionTok.Column, "noise seed must be numeric.");
                var seedValue = ToNumber(seedExpr);
                if (double.IsNaN(seedValue) || double.IsInfinity(seedValue) || Math.Abs(seedValue - Math.Round(seedValue)) > NumericEpsilon || seedValue < 0 || seedValue > uint.MaxValue)
                    throw new CompileError("SEMANTIC", "S181", functionTok.Line, functionTok.Column, "noise seed must be a non-negative integer within uint range.");
                seed = (uint)Math.Round(seedValue);
            }

            if (point.Type != "vec2" && point.Type != "vec3")
                throw new CompileError("SEMANTIC", "S181", functionTok.Line, functionTok.Column, "noise at requires vec2 or vec3 coordinates.");

            var p = ToVector(point);
            var result = p.Length == 2 ? ValueNoise2D(p[0], p[1], seed, functionTok) : ValueNoise3D(p[0], p[1], p[2], seed, functionTok);
            return new ExprResult("double", FormatNumber(result, "double"), $"noise({point.Repr},seed={seed})");
        }

        static double ValueNoise2D(double x, double y, uint seed, Token token)
        {
            var x0 = CheckedFloorToInt(x, token, "S181", "noise");
            var y0 = CheckedFloorToInt(y, token, "S181", "noise");
            var tx = x - x0;
            var ty = y - y0;
            var fx = Fade01(tx);
            var fy = Fade01(ty);
            var n00 = NoiseHash01(x0, y0, 0, seed);
            var n10 = NoiseHash01(x0 + 1, y0, 0, seed);
            var n01 = NoiseHash01(x0, y0 + 1, 0, seed);
            var n11 = NoiseHash01(x0 + 1, y0 + 1, 0, seed);
            return LerpDouble(LerpDouble(n00, n10, fx), LerpDouble(n01, n11, fx), fy);
        }

        static double ValueNoise3D(double x, double y, double z, uint seed, Token token)
        {
            var x0 = CheckedFloorToInt(x, token, "S181", "noise");
            var y0 = CheckedFloorToInt(y, token, "S181", "noise");
            var z0 = CheckedFloorToInt(z, token, "S181", "noise");
            var tx = x - x0;
            var ty = y - y0;
            var tz = z - z0;
            var fx = Fade01(tx);
            var fy = Fade01(ty);
            var fz = Fade01(tz);
            var x00 = LerpDouble(NoiseHash01(x0, y0, z0, seed), NoiseHash01(x0 + 1, y0, z0, seed), fx);
            var x10 = LerpDouble(NoiseHash01(x0, y0 + 1, z0, seed), NoiseHash01(x0 + 1, y0 + 1, z0, seed), fx);
            var x01 = LerpDouble(NoiseHash01(x0, y0, z0 + 1, seed), NoiseHash01(x0 + 1, y0, z0 + 1, seed), fx);
            var x11 = LerpDouble(NoiseHash01(x0, y0 + 1, z0 + 1, seed), NoiseHash01(x0 + 1, y0 + 1, z0 + 1, seed), fx);
            return LerpDouble(LerpDouble(x00, x10, fy), LerpDouble(x01, x11, fy), fz);
        }

        ExprResult ApplyRadiansFromDegrees(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("from", "P190", "Expected from after radians.");
            ExpectWord("degrees", "P191", "Expected degrees after radians from.");
            var value = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "radians from degrees requires numeric degrees.");
            var result = ToNumber(value) * Math.PI / 180.0;
            return new ExprResult("double", FormatNumber(result, "double"), $"radians_from_degrees({value.Repr})");
        }

        ExprResult ApplyDegreesFromRadians(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("from", "P192", "Expected from after degrees.");
            ExpectWord("radians", "P193", "Expected radians after degrees from.");
            var value = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(value.Type) && !IsAngle(value.Type))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "degrees from radians requires numeric or angle radians.");
            var result = ToNumber(value) * 180.0 / Math.PI;
            return new ExprResult("double", FormatNumber(result, "double"), $"degrees_from_radians({value.Repr})");
        }

        ExprResult ApplyPolarFunction(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("radius", "P194", "Expected radius after polar.");
            var radius = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("angle", "P195", "Expected angle in polar expression.");
            var angle = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(radius.Type))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "polar radius must be numeric.");
            if (!IsNumeric(angle.Type) && !IsAngle(angle.Type))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "polar angle must be numeric or angle.");
            var r = ToNumber(radius);
            EnsureFinite(r, functionTok, "S182", "polar radius must be finite.");
            if (r < 0)
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "polar radius cannot be negative.");
            var a = ToNumber(angle);
            return new ExprResult("vec2", FormatVector(new[] { r * Math.Cos(a), r * Math.Sin(a) }), $"polar({radius.Repr},{angle.Repr})");
        }

        ExprResult ApplySphericalFunction(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("radius", "P196", "Expected radius after spherical.");
            var radius = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("yaw", "P197", "Expected yaw in spherical expression.");
            var yaw = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("pitch", "P198", "Expected pitch in spherical expression.");
            var pitch = ParseAddExpression(legacyQuotedStrings);
            if (!IsNumeric(radius.Type))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "spherical radius must be numeric.");
            if ((!IsNumeric(yaw.Type) && !IsAngle(yaw.Type)) || (!IsNumeric(pitch.Type) && !IsAngle(pitch.Type)))
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "spherical yaw and pitch must be numeric or angle values.");
            var r = ToNumber(radius);
            EnsureFinite(r, functionTok, "S182", "spherical radius must be finite.");
            if (r < 0)
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "spherical radius cannot be negative.");
            var y = ToNumber(yaw);
            var p = ToNumber(pitch);
            var cp = Math.Cos(p);
            var result = new[] { r * cp * Math.Cos(y), r * cp * Math.Sin(y), r * Math.Sin(p) };
            return new ExprResult("vec3", FormatVector(result), $"spherical({radius.Repr},{yaw.Repr},{pitch.Repr})");
        }

        ExprResult ApplyAngleBetween(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("between", "P199", "Expected between after angle.");
            var a = ParseAddExpression(legacyQuotedStrings);
            Expect("COMMA", "comma between angle operands");
            var b = ParseAddExpression(legacyQuotedStrings);
            if (!IsVector(a.Type) || !IsVector(b.Type) || a.Type != b.Type)
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "angle between requires matching vector operands.");
            var av = ToVector(a);
            var bv = ToVector(b);
            var al = Math.Sqrt(av.Sum(v => v * v));
            var bl = Math.Sqrt(bv.Sum(v => v * v));
            if (al < NumericEpsilon || bl < NumericEpsilon)
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "angle between requires non-zero vectors.");
            var dot = av.Select((v, i) => v * bv[i]).Sum() / (al * bl);
            dot = Math.Min(Math.Max(dot, -1), 1);
            return new ExprResult("double", FormatNumber(Math.Acos(dot), "double"), $"angle_between({a.Repr},{b.Repr})");
        }

        ExprResult ApplySignedAngle(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("angle", "P200", "Expected angle after signed.");
            ExpectWord("from", "P201", "Expected from after signed angle.");
            var from = ParseAddExpression(legacyQuotedStrings);
            ExpectWord("to", "P202", "Expected to in signed angle expression.");
            var to = ParseAddExpression(legacyQuotedStrings);
            if (from.Type != "vec2" || to.Type != "vec2")
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "signed angle requires vec2 operands.");
            var a = ToVector(from);
            var b = ToVector(to);
            var al = Math.Sqrt(a.Sum(v => v * v));
            var bl = Math.Sqrt(b.Sum(v => v * v));
            if (al < NumericEpsilon || bl < NumericEpsilon)
                throw new CompileError("SEMANTIC", "S182", functionTok.Line, functionTok.Column, "signed angle requires non-zero vectors.");
            var cross = a[0] * b[1] - a[1] * b[0];
            var dot = a[0] * b[0] + a[1] * b[1];
            return new ExprResult("double", FormatNumber(Math.Atan2(cross, dot), "double"), $"signed_angle({from.Repr},{to.Repr})");
        }

        static bool IsScalarUnaryFunctionName(string value)
            => value is "abs" or "sqrt" or "floor" or "ceil" or "round" or "trunc" or "sin" or "cos" or "tan" or "asin" or "acos" or "atan" or "sinh" or "cosh" or "tanh" or "asinh" or "acosh" or "atanh" or "log" or "log10" or "log2" or "exp" or "exp2";

        static bool IsScalarBinaryFunctionName(string value)
            => value is "min" or "max" or "pow" or "atan2";

        static bool IsMathConstantName(string value)
            => value is "pi" or "e";

    }
}
