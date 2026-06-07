using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: TypeSystem.

        static bool IsNumeric(string type) => type is "int" or "float" or "double";

        static bool IsVector(string type) => type is "vec2" or "vec3" or "vec4";

        static bool IsMatrixType(string type) => type is "mat4" or "transform";

        static bool IsQuaternion(string type) => type == "quat";

        static bool IsGeometryType(string type) => type is "rect" or "circle" or "segment" or "line" or "ray" or "sphere" or "aabb" or "plane";

        static bool IsComplex(string type) => type == "complex";

        static bool IsColor(string type) => type == "color";

        static bool IsAngle(string type) => type == "angle";

        static double ToNumber(ExprResult expr)
            => double.Parse(expr.Value, CultureInfo.InvariantCulture);

        static double[] ToVector(ExprResult expr)
        {
            if (!IsVector(expr.Type))
                throw new CompileError("SEMANTIC", "S102", 0, 0, "Expected vector value.");
            var inner = expr.Value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            if (string.IsNullOrWhiteSpace(inner))
                return Array.Empty<double>();
            return inner.Split(',').Select(part => double.Parse(part.Trim(), CultureInfo.InvariantCulture)).ToArray();
        }

        static string FormatVector(double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static bool TrySplitComponentName(string name, out string symbolName, out string component)
        {
            symbolName = "";
            component = "";
            var dot = name.IndexOf('.', StringComparison.Ordinal);
            if (dot < 0)
                return false;
            if (dot == 0 || dot == name.Length - 1 || name.IndexOf('.', dot + 1) >= 0)
                return false;
            symbolName = name[..dot];
            component = name[(dot + 1)..];
            return true;
        }

        static int VectorComponentIndex(string type, string component)
        {
            var index = component switch
            {
                "x" => 0,
                "y" => 1,
                "z" => 2,
                "w" => 3,
                _ => -1,
            };

            return type switch
            {
                "vec2" when index is >= 0 and <= 1 => index,
                "vec3" when index is >= 0 and <= 2 => index,
                "vec4" when index is >= 0 and <= 3 => index,
                _ => -1,
            };
        }

        ExprResult FormatComponentReference(Token token)
        {
            if (!TrySplitComponentName(token.Value, out var symbolName, out var component))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Invalid component reference \"{token.Value}\".");

            if (!_vars.TryGetValue(symbolName, out var info))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Unknown component base symbol \"{symbolName}\".");

            if (!IsVector(info.Type))
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Component access requires vector symbol \"{symbolName}\".");

            var index = VectorComponentIndex(info.Type, component);
            if (index < 0)
                throw new CompileError("SEMANTIC", "S108", token.Line, token.Column, $"Vector {info.Type} does not have component \"{component}\".");

            var values = ToVector(new ExprResult(info.Type, info.Value, $"symbol({symbolName})"));
            return new ExprResult("double", FormatNumber(values[index], "double"), $"component({token.Value})");
        }

        static string VectorTypeForCount(int count) => count switch
        {
            2 => "vec2",
            3 => "vec3",
            4 => "vec4",
            _ => "",
        };

        static double[] IdentityMatrix()
            => new double[]
            {
                1, 0, 0, 0,
                0, 1, 0, 0,
                0, 0, 1, 0,
                0, 0, 0, 1,
            };

        static double[] ToMatrix(ExprResult expr)
        {
            if (!IsMatrixType(expr.Type))
                throw new CompileError("SEMANTIC", "S130", 0, 0, "Expected mat4 or transform value.");
            var inner = expr.Value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            var values = inner.Split(',').Select(part => double.Parse(part.Trim(), CultureInfo.InvariantCulture)).ToArray();
            if (values.Length != 16)
                throw new CompileError("SEMANTIC", "S130", 0, 0, "mat4 value must have 16 components.");
            return values;
        }

        static string FormatMatrix(double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static double[] ToQuaternion(ExprResult expr)
        {
            if (!IsQuaternion(expr.Type))
                throw new CompileError("SEMANTIC", "S150", 0, 0, "Expected quaternion value.");
            var values = ParseBracketedDoubles(expr.Value, "quaternion", 4);
            var len = Math.Sqrt(values.Sum(v => v * v));
            if (Math.Abs(len) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion cannot have zero length.");
            return values.Select(v => v / len).ToArray();
        }

        static string FormatQuaternion(params double[] values)
            => "[" + string.Join(",", values.Select(value => FormatNumber(value, "double"))) + "]";

        static double[] QuaternionFromAxisAngle(double[] axis, double radians)
        {
            if (axis.Length != 3)
                throw new CompileError("SEMANTIC", "S150", 0, 0, "Quaternion axis must be vec3.");
            var len = Math.Sqrt(axis.Sum(v => v * v));
            if (Math.Abs(len) < 0.0000000001)
                throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion axis must be non-zero.");
            var half = radians / 2.0;
            var scale = Math.Sin(half) / len;
            return new[] { axis[0] * scale, axis[1] * scale, axis[2] * scale, Math.Cos(half) };
        }

        static double[] QuaternionMultiply(double[] a, double[] b)
        {
            var ax = a[0]; var ay = a[1]; var az = a[2]; var aw = a[3];
            var bx = b[0]; var by = b[1]; var bz = b[2]; var bw = b[3];
            return new[]
            {
                aw * bx + ax * bw + ay * bz - az * by,
                aw * by - ax * bz + ay * bw + az * bx,
                aw * bz + ax * by - ay * bx + az * bw,
                aw * bw - ax * bx - ay * by - az * bz,
            };
        }

        static double[] RotateVectorByQuaternion(double[] vector, double[] quat)
        {
            if (vector.Length != 3)
                throw new CompileError("SEMANTIC", "S154", 0, 0, "rotate vector requires vec3.");
            var q = quat;
            var v = new[] { vector[0], vector[1], vector[2], 0.0 };
            var qi = new[] { -q[0], -q[1], -q[2], q[3] };
            var r = QuaternionMultiply(QuaternionMultiply(q, v), qi);
            return new[] { r[0], r[1], r[2] };
        }

        static double[] SlerpQuaternion(double[] a, double[] b, double t)
        {
            var q1 = a.ToArray();
            var q2 = b.ToArray();
            var dot = q1.Select((v, i) => v * q2[i]).Sum();
            if (dot < 0.0)
            {
                q2 = q2.Select(v => -v).ToArray();
                dot = -dot;
            }

            if (dot > 0.9995)
            {
                var linear = q1.Select((v, i) => v + t * (q2[i] - v)).ToArray();
                var len = Math.Sqrt(linear.Sum(v => v * v));
                if (Math.Abs(len) < NumericEpsilon)
                    throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion slerp produced zero length result.");
                return linear.Select(v => v / len).ToArray();
            }

            dot = Math.Clamp(dot, -1.0, 1.0);
            var theta0 = Math.Acos(dot);
            var theta = theta0 * t;
            var sinTheta = Math.Sin(theta);
            var sinTheta0 = Math.Sin(theta0);
            var s0 = Math.Cos(theta) - dot * sinTheta / sinTheta0;
            var s1 = sinTheta / sinTheta0;
            var result = q1.Select((v, i) => s0 * v + s1 * q2[i]).ToArray();
            var resultLen = Math.Sqrt(result.Sum(v => v * v));
            if (Math.Abs(resultLen) < NumericEpsilon)
                throw new CompileError("SEMANTIC", "S152", 0, 0, "Quaternion slerp produced zero length result.");
            return result.Select(v => v / resultLen).ToArray();
        }

        static double[] EulerFromQuaternion(double[] q)
        {
            var x = q[0]; var y = q[1]; var z = q[2]; var w = q[3];

            var sinrCosp = 2.0 * (w * x + y * z);
            var cosrCosp = 1.0 - 2.0 * (x * x + y * y);
            var roll = Math.Atan2(sinrCosp, cosrCosp);

            var sinp = 2.0 * (w * y - z * x);
            var pitch = Math.Abs(sinp) >= 1.0 ? Math.CopySign(Math.PI / 2.0, sinp) : Math.Asin(sinp);

            var sinyCosp = 2.0 * (w * z + x * y);
            var cosyCosp = 1.0 - 2.0 * (y * y + z * z);
            var yaw = Math.Atan2(sinyCosp, cosyCosp);

            return new[] { roll, pitch, yaw };
        }

        static double[] ParseBracketedDoubles(string value, string label, int expectedCount)
        {
            var inner = value.Trim();
            if (inner.StartsWith("[") && inner.EndsWith("]"))
                inner = inner[1..^1];
            var parts = inner.Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length != expectedCount)
                throw new CompileError("SEMANTIC", "S150", 0, 0, $"Expected {expectedCount} values in {label}.");
            return parts.Select(part => double.Parse(part, CultureInfo.InvariantCulture)).ToArray();
        }

        static string FormatRect(double[] origin, double[] size)
            => $"rect({FormatVector(origin)},{FormatVector(size)})";

        static string FormatCircle(double[] center, double radius)
            => $"circle({FormatVector(center)},{FormatNumber(radius, "double")})";

        static (double X, double Y, double W, double H) ToRect(ExprResult expr)
        {
            if (expr.Type != "rect")
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Expected rect value.");
            var value = expr.Value.Trim();
            if (!value.StartsWith("rect(", StringComparison.Ordinal) || !value.EndsWith(")", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Invalid rect value.");
            var inner = value[5..^1];
            var split = inner.IndexOf("],[", StringComparison.Ordinal);
            if (split < 0)
                throw new CompileError("SEMANTIC", "S160", 0, 0, "Invalid rect value.");
            var origin = ToVector(new ExprResult("vec2", inner[..(split + 1)], "rect_origin"));
            var size = ToVector(new ExprResult("vec2", inner[(split + 2)..], "rect_size"));
            return (origin[0], origin[1], size[0], size[1]);
        }

        static (double X, double Y, double R) ToCircle(ExprResult expr)
        {
            if (expr.Type != "circle")
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Expected circle value.");
            var value = expr.Value.Trim();
            if (!value.StartsWith("circle(", StringComparison.Ordinal) || !value.EndsWith(")", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Invalid circle value.");
            var inner = value[7..^1];
            var split = inner.LastIndexOf(",", StringComparison.Ordinal);
            if (split < 0)
                throw new CompileError("SEMANTIC", "S162", 0, 0, "Invalid circle value.");
            var center = ToVector(new ExprResult("vec2", inner[..split], "circle_center"));
            var radius = double.Parse(inner[(split + 1)..], CultureInfo.InvariantCulture);
            return (center[0], center[1], radius);
        }

        static string FormatSegment(double[] a, double[] b)
            => FormatVector(new[] { a[0], a[1], b[0], b[1] });

        static string FormatRay(double[] origin, double[] direction)
            => FormatVector(new[] { origin[0], origin[1], origin[2], direction[0], direction[1], direction[2] });

        static string FormatSphere(double[] center, double radius)
            => FormatVector(new[] { center[0], center[1], center[2], radius });

        static string FormatAabb(double[] center, double[] size)
            => FormatVector(new[] { center[0], center[1], center[2], size[0], size[1], size[2] });

        static string FormatPlane(double[] normal, double distance)
            => FormatVector(new[] { normal[0], normal[1], normal[2], distance });

        static (double X1, double Y1, double X2, double Y2) ToSegment(ExprResult expr)
        {
            var values = ParseBracketedDoubles(expr.Value, expr.Type, 4);
            return (values[0], values[1], values[2], values[3]);
        }

        static (double OX, double OY, double OZ, double DX, double DY, double DZ) ToRay(ExprResult expr)
        {
            var values = ParseBracketedDoubles(expr.Value, "ray", 6);
            return (values[0], values[1], values[2], values[3], values[4], values[5]);
        }

        static (double X, double Y, double Z, double R) ToSphere(ExprResult expr)
        {
            var values = ParseBracketedDoubles(expr.Value, "sphere", 4);
            return (values[0], values[1], values[2], values[3]);
        }

        static (double X, double Y, double Z, double SX, double SY, double SZ) ToAabb(ExprResult expr)
        {
            var values = ParseBracketedDoubles(expr.Value, "aabb", 6);
            return (values[0], values[1], values[2], values[3], values[4], values[5]);
        }

        static (double NX, double NY, double NZ, double D) ToPlane(ExprResult expr)
        {
            var values = ParseBracketedDoubles(expr.Value, "plane", 4);
            return (values[0], values[1], values[2], values[3]);
        }

        static (double MinX, double MinY, double MinZ, double MaxX, double MaxY, double MaxZ) AabbBounds((double X, double Y, double Z, double SX, double SY, double SZ) box)
            => (box.X - box.SX / 2, box.Y - box.SY / 2, box.Z - box.SZ / 2, box.X + box.SX / 2, box.Y + box.SY / 2, box.Z + box.SZ / 2);

        static (double R, double I) ToComplex(ExprResult expr)
        {
            if (IsNumeric(expr.Type))
                return (ToNumber(expr), 0);
            if (!IsComplex(expr.Type))
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Expected complex value.");
            var raw = expr.Value.Trim();
            if (!raw.EndsWith("i", StringComparison.Ordinal))
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Invalid complex value.");
            var body = raw[..^1];
            var split = -1;
            for (var i = 1; i < body.Length; i++)
                if (body[i] is '+' or '-')
                    split = i;
            if (split < 0)
                throw new CompileError("SEMANTIC", "S170", 0, 0, "Invalid complex value.");
            var real = double.Parse(body[..split], CultureInfo.InvariantCulture);
            var imag = double.Parse(body[split..], CultureInfo.InvariantCulture);
            return (real, imag);
        }

        static string FormatComplex(double real, double imag)
        {
            if (Math.Abs(real) < NumericEpsilon)
                real = 0;
            if (Math.Abs(imag) < NumericEpsilon)
                imag = 0;
            var r = FormatNumber(real, "double");
            var absI = FormatNumber(Math.Abs(imag), "double");
            var sign = imag < 0 ? "-" : "+";
            return $"{r}{sign}{absI}i";
        }

        static double[] MultiplyMatrix(double[] a, double[] b)
        {
            var result = new double[16];
            for (var row = 0; row < 4; row++)
                for (var col = 0; col < 4; col++)
                    result[row * 4 + col] =
                        a[row * 4 + 0] * b[0 * 4 + col] +
                        a[row * 4 + 1] * b[1 * 4 + col] +
                        a[row * 4 + 2] * b[2 * 4 + col] +
                        a[row * 4 + 3] * b[3 * 4 + col];
            return result;
        }

        static double[] TranslationMatrix(double[] v)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S131", 0, 0, "translate requires vec3 value.");
            var m = IdentityMatrix();
            m[3] = v[0];
            m[7] = v[1];
            m[11] = v[2];
            return m;
        }

        static double[] ScaleMatrix(double[] v)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S131", 0, 0, "scale requires vec3 value.");
            var m = IdentityMatrix();
            m[0] = v[0];
            m[5] = v[1];
            m[10] = v[2];
            return m;
        }

        static double[] RotationMatrix(string axis, double radians)
        {
            var c = Math.Cos(radians);
            var s = Math.Sin(radians);
            var m = IdentityMatrix();
            switch (axis)
            {
                case "x":
                    m[5] = c; m[6] = -s; m[9] = s; m[10] = c;
                    break;
                case "y":
                    m[0] = c; m[2] = s; m[8] = -s; m[10] = c;
                    break;
                case "z":
                    m[0] = c; m[1] = -s; m[4] = s; m[5] = c;
                    break;
                default:
                    throw new CompileError("SEMANTIC", "S132", 0, 0, "rotate axis must be x, y, or z.");
            }
            return m;
        }

        static double[] TransformVector(double[] m, double[] v, bool point)
        {
            if (v.Length != 3)
                throw new CompileError("SEMANTIC", "S133", 0, 0, "transform point/direction requires vec3 value.");
            var w = point ? 1.0 : 0.0;
            return new[]
            {
                m[0] * v[0] + m[1] * v[1] + m[2] * v[2] + m[3] * w,
                m[4] * v[0] + m[5] * v[1] + m[6] * v[2] + m[7] * w,
                m[8] * v[0] + m[9] * v[1] + m[10] * v[2] + m[11] * w,
            };
        }

        static string PromoteNumericType(string left, string right, string op)
        {
            if (op == "/" && left == "int" && right == "int")
                return "double";
            if (left == "double" || right == "double")
                return "double";
            if (left == "float" || right == "float")
                return "float";
            return "int";
        }

        static string FormatNumber(double value, string type)
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
                throw new CompileError("SEMANTIC", "S094", 0, 0, "Math result must be finite.");

            if (Math.Abs(value) < NumericEpsilon)
                value = 0;

            var rounded = Math.Round(value);
            if (Math.Abs(value - rounded) < NumericEpsilon)
                value = rounded;

            if (type == "int")
            {
                if (value > long.MaxValue || value < long.MinValue)
                    throw new CompileError("SEMANTIC", "S094", 0, 0, "Integer math result is outside the supported range.");
                return ((long)Math.Round(value)).ToString(CultureInfo.InvariantCulture);
            }

            return value.ToString("0.##########", CultureInfo.InvariantCulture);
        }

        static double Clamp01(double value) => Math.Min(Math.Max(value, 0), 1);

        static bool IsNearlyZero(double value) => Math.Abs(value) < NumericEpsilon;

        static double SmoothStep01(double value)
        {
            var t = Clamp01(value);
            return t * t * (3 - 2 * t);
        }

        static double SmootherStep01(double value)
        {
            var t = Clamp01(value);
            return t * t * t * (t * (t * 6 - 15) + 10);
        }

        static double LerpDouble(double a, double b, double t) => a + (b - a) * t;

        static double Fade01(double value) => SmootherStep01(value);

        static void EnsureFinite(double value, Token token, string code, string message)
        {
            if (double.IsNaN(value) || double.IsInfinity(value))
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, message);
        }

        uint NextRandomUInt()
        {
            unchecked
            {
                _randomState = _randomState * 1664525u + 1013904223u;
                return _randomState;
            }
        }

        double NextRandomUnit() => NextRandomUInt() / 4294967296.0;

        static uint NoiseHash(int x, int y, int z, uint seed)
        {
            unchecked
            {
                uint h = 2166136261u ^ seed;
                h = (h ^ (uint)x) * 16777619u;
                h = (h ^ (uint)y) * 16777619u;
                h = (h ^ (uint)z) * 16777619u;
                h ^= h >> 13;
                h *= 1274126177u;
                h ^= h >> 16;
                return h;
            }
        }

        static double NoiseHash01(int x, int y, int z, uint seed)
            => NoiseHash(x, y, z, seed) / 4294967295.0;

        static int CheckedFloorToInt(double value, Token token, string code, string name)
        {
            EnsureFinite(value, token, code, $"{name} coordinate must be finite.");
            var floored = Math.Floor(value);
            if (floored < int.MinValue || floored > int.MaxValue)
                throw new CompileError("SEMANTIC", code, token.Line, token.Column, $"{name} coordinate is outside supported noise range.");
            return (int)floored;
        }

        static string FormatValue(ExprResult expr) => expr.Type == "bool" ? expr.Value.ToLowerInvariant() : expr.Value;

    }
}
