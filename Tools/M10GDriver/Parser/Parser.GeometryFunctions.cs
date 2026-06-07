using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: GeometryFunctions.

        static bool IsVectorUnaryFunctionName(string value)
            => value is "length" or "normalize";

        static bool IsVectorBinaryFunctionName(string value)
            => value is "dot" or "cross";

        static bool IsAdvancedMathFunctionName(string value)
            => value is "saturate" or "sign" or "fract" or "step" or "smoothstep" or "smootherstep" or "inverse" or "remap" or "clamped" or "lerp" or "ease" or "distance" or "reflect" or "project" or "clamp" or "component" or "bit" or "shift" or "quadratic" or "cubic" or "catmull" or "translate" or "scale" or "rotate" or "matmul" or "compose" or "slerp" or "euler" or "random" or "noise" or "radians" or "degrees" or "polar" or "spherical" or "angle" or "signed";

        static bool IsComplexFunctionName(string value)
            => value is "real" or "imag" or "magnitude" or "phase";

        static bool IsGeometryFunctionName(string value)
            => value is "point" or "rect" or "closest" or "segment" or "ray" or "sphere" or "aabb";

        ExprResult ApplyVectorUnaryFunction(Token functionTok, ExprResult value)
        {
            if (!IsVector(value.Type))
                throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a vector operand.");

            var vector = ToVector(value);
            var len = Math.Sqrt(vector.Sum(component => component * component));

            if (functionTok.Value == "length")
                return new ExprResult("double", FormatNumber(len, "double"), $"length({value.Repr})");

            if (functionTok.Value == "normalize")
            {
                if (Math.Abs(len) < 0.0000000001)
                    throw new CompileError("SEMANTIC", "S103", functionTok.Line, functionTok.Column, "normalize requires a non-zero vector.");
                var result = vector.Select(component => component / len).ToArray();
                return new ExprResult(value.Type, FormatVector(result), $"normalize({value.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ApplyVectorBinaryFunction(Token functionTok, ExprResult left, ExprResult right)
        {
            if (!IsVector(left.Type) || !IsVector(right.Type))
                throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires vector operands.");
            if (left.Type != right.Type && functionTok.Value == "dot")
                throw new CompileError("SEMANTIC", "S104", functionTok.Line, functionTok.Column, "dot requires matching vector dimensions.");

            var l = ToVector(left);
            var r = ToVector(right);

            if (functionTok.Value == "dot")
            {
                var result = l.Select((value, index) => value * r[index]).Sum();
                return new ExprResult("double", FormatNumber(result, "double"), $"dot({left.Repr},{right.Repr})");
            }

            if (functionTok.Value == "cross")
            {
                if (left.Type != "vec3" || right.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S105", functionTok.Line, functionTok.Column, "cross requires vec3 operands.");
                var result = new[]
                {
                    l[1] * r[2] - l[2] * r[1],
                    l[2] * r[0] - l[0] * r[2],
                    l[0] * r[1] - l[1] * r[0],
                };
                return new ExprResult("vec3", FormatVector(result), $"cross({left.Repr},{right.Repr})");
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ApplyQuaternionRotateVector(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("vector", "P154", "Expected vector after rotate.");
            var vector = ParseAddExpression(legacyQuotedStrings);
            if (vector.Type != "vec3")
                throw new CompileError("SEMANTIC", "S154", functionTok.Line, functionTok.Column, "rotate vector requires vec3 value.");
            ExpectWord("by", "P155", "Expected by in rotate vector expression.");
            var quat = ParseAddExpression(legacyQuotedStrings);
            if (quat.Type != "quat")
                throw new CompileError("SEMANTIC", "S154", functionTok.Line, functionTok.Column, "rotate vector requires quaternion operand.");
            var result = RotateVectorByQuaternion(ToVector(vector), ToQuaternion(quat));
            return new ExprResult("vec3", FormatVector(result), $"rotate_vector({vector.Repr},{quat.Repr})");
        }

        ExprResult ApplyQuaternionSlerp(Token functionTok, ExprResult a, ExprResult b, ExprResult t)
        {
            if (a.Type != "quat" || b.Type != "quat")
                throw new CompileError("SEMANTIC", "S153", functionTok.Line, functionTok.Column, "slerp requires quaternion operands.");
            if (!IsNumeric(t.Type))
                throw new CompileError("SEMANTIC", "S153", functionTok.Line, functionTok.Column, "slerp t must be numeric.");
            var result = SlerpQuaternion(ToQuaternion(a), ToQuaternion(b), ToNumber(t));
            return new ExprResult("quat", FormatQuaternion(result), $"slerp({a.Repr},{b.Repr},{t.Repr})");
        }

        ExprResult ApplyEulerFromQuat(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("from", "P156", "Expected from after euler.");
            ExpectWord("quat", "P157", "Expected quat after euler from.");
            var quat = ParseAddExpression(legacyQuotedStrings);
            if (quat.Type != "quat")
                throw new CompileError("SEMANTIC", "S155", functionTok.Line, functionTok.Column, "euler from quat requires quaternion operand.");
            return new ExprResult("vec3", FormatVector(EulerFromQuaternion(ToQuaternion(quat))), $"euler_from_quat({quat.Repr})");
        }

        ExprResult ParseComplexFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            var value = ParseUnaryExpression(legacyQuotedStrings);
            if (value.Type != "complex" && !IsNumeric(value.Type))
                throw new CompileError("SEMANTIC", "S170", functionTok.Line, functionTok.Column, $"{functionTok.Value} requires a complex operand.");
            var c = ToComplex(value);
            var result = functionTok.Value switch
            {
                "real" => c.R,
                "imag" => c.I,
                "magnitude" => Math.Sqrt(c.R * c.R + c.I * c.I),
                "phase" => Math.Atan2(c.I, c.R),
                _ => throw new CompileError("SEMANTIC", "S170", functionTok.Line, functionTok.Column, $"Unknown complex function {functionTok.Value}.")
            };
            return new ExprResult("double", FormatNumber(result, "double"), $"{functionTok.Value}({value.Repr})");
        }

        ExprResult ParseGeometryFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            return functionTok.Value switch
            {
                "point" => ApplyPointInside(functionTok, legacyQuotedStrings),
                "rect" => ApplyRectIntersects(functionTok, legacyQuotedStrings),
                "segment" => ApplySegmentIntersects(functionTok, legacyQuotedStrings),
                "ray" => ApplyRayIntersects(functionTok, legacyQuotedStrings),
                "sphere" => ApplySphereIntersects(functionTok, legacyQuotedStrings),
                "aabb" => ApplyAabbIntersects(functionTok, legacyQuotedStrings),
                "closest" => ApplyClosestPoint(functionTok, legacyQuotedStrings),
                _ => throw new CompileError("SEMANTIC", "S160", functionTok.Line, functionTok.Column, $"Unknown geometry function {functionTok.Value}.")
            };
        }

        ExprResult ApplyPointInside(Token functionTok, bool legacyQuotedStrings)
        {
            var point = ParseAddExpression(legacyQuotedStrings);
            if (point.Type != "vec2")
                throw new CompileError("SEMANTIC", "S164", functionTok.Line, functionTok.Column, "point inside requires vec2 point.");
            ExpectWord("inside", "P165", "Expected inside in point inside expression.");
            var shape = ParseAddExpression(legacyQuotedStrings);
            var p = ToVector(point);
            var inside = shape.Type switch
            {
                "rect" => PointInsideRect(p, ToRect(shape)),
                "circle" => PointInsideCircle(p, ToCircle(shape)),
                _ => throw new CompileError("SEMANTIC", "S164", functionTok.Line, functionTok.Column, "point inside requires rect or circle shape.")
            };
            return new ExprResult("bool", inside.ToString().ToLowerInvariant(), $"point_inside({point.Repr},{shape.Repr})");
        }

        ExprResult ApplyRectIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var left = ParseAddExpression(legacyQuotedStrings);
            if (left.Type != "rect")
                throw new CompileError("SEMANTIC", "S165", functionTok.Line, functionTok.Column, "rect intersects requires rect operand.");
            ExpectWord("intersects", "P166", "Expected intersects in rect expression.");
            var right = ParseAddExpression(legacyQuotedStrings);
            var hit = right.Type switch
            {
                "rect" => RectIntersects(ToRect(left), ToRect(right)),
                "circle" => RectIntersectsCircle(ToRect(left), ToCircle(right)),
                _ => throw new CompileError("SEMANTIC", "S165", functionTok.Line, functionTok.Column, "rect intersects requires rect or circle operand.")
            };
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"rect_intersects({left.Repr},{right.Repr})");
        }

        ExprResult ApplySegmentIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var left = ParseAddExpression(legacyQuotedStrings);
            if (left.Type != "segment")
                throw new CompileError("SEMANTIC", "S202", functionTok.Line, functionTok.Column, "segment intersects requires segment operand.");
            ExpectWord("intersects", "P208", "Expected intersects in segment expression.");
            var right = ParseAddExpression(legacyQuotedStrings);
            if (right.Type != "segment")
                throw new CompileError("SEMANTIC", "S202", functionTok.Line, functionTok.Column, "segment intersects requires another segment.");
            var hit = SegmentIntersectsSegment(ToSegment(left), ToSegment(right));
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"segment_intersects({left.Repr},{right.Repr})");
        }

        ExprResult ApplyRayIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var ray = ParseAddExpression(legacyQuotedStrings);
            if (ray.Type != "ray")
                throw new CompileError("SEMANTIC", "S203", functionTok.Line, functionTok.Column, "ray intersects requires ray operand.");
            ExpectWord("intersects", "P209", "Expected intersects in ray expression.");
            var target = ParseAddExpression(legacyQuotedStrings);
            var hit = target.Type switch
            {
                "sphere" => RayIntersectsSphere(ToRay(ray), ToSphere(target)),
                "aabb" => RayIntersectsAabb(ToRay(ray), ToAabb(target)),
                "plane" => RayIntersectsPlane(ToRay(ray), ToPlane(target)),
                _ => throw new CompileError("SEMANTIC", "S203", functionTok.Line, functionTok.Column, "ray intersects requires sphere, aabb, or plane target.")
            };
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"ray_intersects({ray.Repr},{target.Repr})");
        }

        ExprResult ApplySphereIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var sphere = ParseAddExpression(legacyQuotedStrings);
            if (sphere.Type != "sphere")
                throw new CompileError("SEMANTIC", "S204", functionTok.Line, functionTok.Column, "sphere intersects requires sphere operand.");
            ExpectWord("intersects", "P210", "Expected intersects in sphere expression.");
            var target = ParseAddExpression(legacyQuotedStrings);
            var hit = target.Type switch
            {
                "sphere" => SphereIntersectsSphere(ToSphere(sphere), ToSphere(target)),
                "aabb" => SphereIntersectsAabb(ToSphere(sphere), ToAabb(target)),
                _ => throw new CompileError("SEMANTIC", "S204", functionTok.Line, functionTok.Column, "sphere intersects requires sphere or aabb target.")
            };
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"sphere_intersects({sphere.Repr},{target.Repr})");
        }

        ExprResult ApplyAabbIntersects(Token functionTok, bool legacyQuotedStrings)
        {
            var box = ParseAddExpression(legacyQuotedStrings);
            if (box.Type != "aabb")
                throw new CompileError("SEMANTIC", "S205", functionTok.Line, functionTok.Column, "aabb intersects requires aabb operand.");
            ExpectWord("intersects", "P211", "Expected intersects in aabb expression.");
            var target = ParseAddExpression(legacyQuotedStrings);
            var hit = target.Type switch
            {
                "aabb" => AabbIntersectsAabb(ToAabb(box), ToAabb(target)),
                "sphere" => SphereIntersectsAabb(ToSphere(target), ToAabb(box)),
                _ => throw new CompileError("SEMANTIC", "S205", functionTok.Line, functionTok.Column, "aabb intersects requires aabb or sphere target.")
            };
            return new ExprResult("bool", hit.ToString().ToLowerInvariant(), $"aabb_intersects({box.Repr},{target.Repr})");
        }

        ExprResult ApplyClosestPoint(Token functionTok, bool legacyQuotedStrings)
        {
            ExpectWord("point", "P167", "Expected point after closest.");
            ExpectWord("on", "P168", "Expected on after closest point.");
            if (CurrentWordIs("rect"))
            {
                Advance();
                var rect = ParseAddExpression(legacyQuotedStrings);
                if (rect.Type != "rect")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on rect requires rect operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec2.");
                return new ExprResult("vec2", FormatVector(ClosestPointOnRect(ToRect(rect), ToVector(point))), $"closest_rect({rect.Repr},{point.Repr})");
            }
            if (CurrentWordIs("circle"))
            {
                Advance();
                var circle = ParseAddExpression(legacyQuotedStrings);
                if (circle.Type != "circle")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on circle requires circle operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec2.");
                return new ExprResult("vec2", FormatVector(ClosestPointOnCircle(ToCircle(circle), ToVector(point))), $"closest_circle({circle.Repr},{point.Repr})");
            }
            if (CurrentWordIs("segment"))
            {
                Advance();
                var segment = ParseAddExpression(legacyQuotedStrings);
                if (segment.Type != "segment")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on segment requires segment operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec2.");
                return new ExprResult("vec2", FormatVector(ClosestPointOnSegment(ToSegment(segment), ToVector(point))), $"closest_segment({segment.Repr},{point.Repr})");
            }
            if (CurrentWordIs("sphere"))
            {
                Advance();
                var sphere = ParseAddExpression(legacyQuotedStrings);
                if (sphere.Type != "sphere")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on sphere requires sphere operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec3.");
                return new ExprResult("vec3", FormatVector(ClosestPointOnSphere(ToSphere(sphere), ToVector(point))), $"closest_sphere({sphere.Repr},{point.Repr})");
            }
            if (CurrentWordIs("aabb"))
            {
                Advance();
                var box = ParseAddExpression(legacyQuotedStrings);
                if (box.Type != "aabb")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point on aabb requires aabb operand.");
                ExpectWord("to", "P169", "Expected to in closest point expression.");
                var point = ParseAddExpression(legacyQuotedStrings);
                if (point.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S166", functionTok.Line, functionTok.Column, "closest point target must be vec3.");
                return new ExprResult("vec3", FormatVector(ClosestPointOnAabb(ToAabb(box), ToVector(point))), $"closest_aabb({box.Repr},{point.Repr})");
            }
            throw new CompileError("PARSE", "P168", Current.Line, Current.Column, "Expected rect, circle, segment, sphere, or aabb after closest point on.");
        }

        static bool PointInsideRect(double[] point, (double X, double Y, double W, double H) rect)
            => point[0] >= rect.X && point[0] <= rect.X + rect.W && point[1] >= rect.Y && point[1] <= rect.Y + rect.H;

        static bool PointInsideCircle(double[] point, (double X, double Y, double R) circle)
        {
            var dx = point[0] - circle.X;
            var dy = point[1] - circle.Y;
            return dx * dx + dy * dy <= circle.R * circle.R + 0.0000000001;
        }

        static bool RectIntersects((double X, double Y, double W, double H) a, (double X, double Y, double W, double H) b)
            => a.X <= b.X + b.W && a.X + a.W >= b.X && a.Y <= b.Y + b.H && a.Y + a.H >= b.Y;

        static double[] ClosestPointOnRect((double X, double Y, double W, double H) rect, double[] point)
            => new[] { Math.Min(Math.Max(point[0], rect.X), rect.X + rect.W), Math.Min(Math.Max(point[1], rect.Y), rect.Y + rect.H) };

        static double[] ClosestPointOnCircle((double X, double Y, double R) circle, double[] point)
        {
            var dx = point[0] - circle.X;
            var dy = point[1] - circle.Y;
            var len = Math.Sqrt(dx * dx + dy * dy);
            if (Math.Abs(len) < 0.0000000001)
                return new[] { circle.X + circle.R, circle.Y };
            return new[] { circle.X + dx / len * circle.R, circle.Y + dy / len * circle.R };
        }

        static double VectorLength(double[] vector)
            => Math.Sqrt(vector.Sum(v => v * v));

        static double DistanceSquared(double[] a, double[] b)
            => a.Select((component, index) => component - b[index]).Sum(delta => delta * delta);

        static double Cross2(double ax, double ay, double bx, double by)
            => ax * by - ay * bx;

        static bool CircleIntersectsCircle((double X, double Y, double R) a, (double X, double Y, double R) b)
        {
            var dx = a.X - b.X;
            var dy = a.Y - b.Y;
            var r = a.R + b.R;
            return dx * dx + dy * dy <= r * r + NumericEpsilon;
        }

        static bool RectIntersectsCircle((double X, double Y, double W, double H) rect, (double X, double Y, double R) circle)
        {
            var closest = ClosestPointOnRect(rect, new[] { circle.X, circle.Y });
            var dx = closest[0] - circle.X;
            var dy = closest[1] - circle.Y;
            return dx * dx + dy * dy <= circle.R * circle.R + NumericEpsilon;
        }

        static bool SegmentIntersectsSegment((double X1, double Y1, double X2, double Y2) a, (double X1, double Y1, double X2, double Y2) b)
        {
            var ax = a.X2 - a.X1;
            var ay = a.Y2 - a.Y1;
            var bx = b.X2 - b.X1;
            var by = b.Y2 - b.Y1;
            var denom = Cross2(ax, ay, bx, by);
            var cx = b.X1 - a.X1;
            var cy = b.Y1 - a.Y1;
            if (Math.Abs(denom) < NumericEpsilon)
            {
                if (Math.Abs(Cross2(cx, cy, ax, ay)) >= NumericEpsilon)
                    return false;
                var dotA = cx * ax + cy * ay;
                var dotB = (b.X2 - a.X1) * ax + (b.Y2 - a.Y1) * ay;
                var lenSq = ax * ax + ay * ay;
                return Math.Max(0, Math.Min(dotA, dotB)) <= Math.Min(lenSq, Math.Max(dotA, dotB)) + NumericEpsilon;
            }
            var t = Cross2(cx, cy, bx, by) / denom;
            var u = Cross2(cx, cy, ax, ay) / denom;
            return t >= -NumericEpsilon && t <= 1 + NumericEpsilon && u >= -NumericEpsilon && u <= 1 + NumericEpsilon;
        }

        static double DistancePointToLine(double[] point, (double X1, double Y1, double X2, double Y2) line)
        {
            var dx = line.X2 - line.X1;
            var dy = line.Y2 - line.Y1;
            return Math.Abs(Cross2(point[0] - line.X1, point[1] - line.Y1, dx, dy)) / Math.Sqrt(dx * dx + dy * dy);
        }

        static double[] ClosestPointOnSegment((double X1, double Y1, double X2, double Y2) segment, double[] point)
        {
            var dx = segment.X2 - segment.X1;
            var dy = segment.Y2 - segment.Y1;
            var lenSq = dx * dx + dy * dy;
            var t = ((point[0] - segment.X1) * dx + (point[1] - segment.Y1) * dy) / lenSq;
            t = Math.Min(Math.Max(t, 0), 1);
            return new[] { segment.X1 + dx * t, segment.Y1 + dy * t };
        }

        static bool SphereIntersectsSphere((double X, double Y, double Z, double R) a, (double X, double Y, double Z, double R) b)
        {
            var dx = a.X - b.X;
            var dy = a.Y - b.Y;
            var dz = a.Z - b.Z;
            var r = a.R + b.R;
            return dx * dx + dy * dy + dz * dz <= r * r + NumericEpsilon;
        }

        static double[] ClosestPointOnAabb((double X, double Y, double Z, double SX, double SY, double SZ) box, double[] point)
        {
            var b = AabbBounds(box);
            return new[]
            {
                Math.Min(Math.Max(point[0], b.MinX), b.MaxX),
                Math.Min(Math.Max(point[1], b.MinY), b.MaxY),
                Math.Min(Math.Max(point[2], b.MinZ), b.MaxZ)
            };
        }

        static double[] ClosestPointOnSphere((double X, double Y, double Z, double R) sphere, double[] point)
        {
            var dx = point[0] - sphere.X;
            var dy = point[1] - sphere.Y;
            var dz = point[2] - sphere.Z;
            var len = Math.Sqrt(dx * dx + dy * dy + dz * dz);
            if (len < NumericEpsilon)
                return new[] { sphere.X + sphere.R, sphere.Y, sphere.Z };
            return new[] { sphere.X + dx / len * sphere.R, sphere.Y + dy / len * sphere.R, sphere.Z + dz / len * sphere.R };
        }

        static bool AabbIntersectsAabb((double X, double Y, double Z, double SX, double SY, double SZ) a, (double X, double Y, double Z, double SX, double SY, double SZ) b)
        {
            var ab = AabbBounds(a);
            var bb = AabbBounds(b);
            return ab.MinX <= bb.MaxX && ab.MaxX >= bb.MinX &&
                   ab.MinY <= bb.MaxY && ab.MaxY >= bb.MinY &&
                   ab.MinZ <= bb.MaxZ && ab.MaxZ >= bb.MinZ;
        }

        static bool SphereIntersectsAabb((double X, double Y, double Z, double R) sphere, (double X, double Y, double Z, double SX, double SY, double SZ) box)
        {
            var closest = ClosestPointOnAabb(box, new[] { sphere.X, sphere.Y, sphere.Z });
            var dx = closest[0] - sphere.X;
            var dy = closest[1] - sphere.Y;
            var dz = closest[2] - sphere.Z;
            return dx * dx + dy * dy + dz * dz <= sphere.R * sphere.R + NumericEpsilon;
        }

        static bool RayIntersectsSphere((double OX, double OY, double OZ, double DX, double DY, double DZ) ray, (double X, double Y, double Z, double R) sphere)
        {
            var ox = ray.OX - sphere.X;
            var oy = ray.OY - sphere.Y;
            var oz = ray.OZ - sphere.Z;
            var b = ox * ray.DX + oy * ray.DY + oz * ray.DZ;
            var c = ox * ox + oy * oy + oz * oz - sphere.R * sphere.R;
            if (c <= 0)
                return true;
            var disc = b * b - c;
            return disc >= -NumericEpsilon && -b + Math.Sqrt(Math.Max(0, disc)) >= -NumericEpsilon;
        }

        static bool RayIntersectsPlane((double OX, double OY, double OZ, double DX, double DY, double DZ) ray, (double NX, double NY, double NZ, double D) plane)
        {
            var denom = plane.NX * ray.DX + plane.NY * ray.DY + plane.NZ * ray.DZ;
            if (Math.Abs(denom) < NumericEpsilon)
                return false;
            var t = -(plane.NX * ray.OX + plane.NY * ray.OY + plane.NZ * ray.OZ + plane.D) / denom;
            return t >= -NumericEpsilon;
        }

        static bool RayIntersectsAabb((double OX, double OY, double OZ, double DX, double DY, double DZ) ray, (double X, double Y, double Z, double SX, double SY, double SZ) box)
        {
            var b = AabbBounds(box);
            var tMin = double.NegativeInfinity;
            var tMax = double.PositiveInfinity;
            bool Slab(double origin, double direction, double min, double max)
            {
                if (Math.Abs(direction) < NumericEpsilon)
                    return origin >= min && origin <= max;
                var t1 = (min - origin) / direction;
                var t2 = (max - origin) / direction;
                if (t1 > t2) (t1, t2) = (t2, t1);
                tMin = Math.Max(tMin, t1);
                tMax = Math.Min(tMax, t2);
                return tMin <= tMax + NumericEpsilon;
            }
            return Slab(ray.OX, ray.DX, b.MinX, b.MaxX) &&
                   Slab(ray.OY, ray.DY, b.MinY, b.MaxY) &&
                   Slab(ray.OZ, ray.DZ, b.MinZ, b.MaxZ) &&
                   tMax >= -NumericEpsilon;
        }

    }
}
