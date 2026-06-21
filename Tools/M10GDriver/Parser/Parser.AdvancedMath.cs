using System.Globalization;
using System.Text;

static partial class Program
{
    sealed partial class Parser
    {
        // M18FG parser split: AdvancedMath.

        ExprResult ParseAdvancedMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            switch (functionTok.Value)
            {
                case "random":
                    return ApplyRandomFunction(functionTok, legacyQuotedStrings);
                case "noise":
                    return ApplyNoiseFunction(functionTok, legacyQuotedStrings);
                case "radians":
                    return ApplyRadiansFromDegrees(functionTok, legacyQuotedStrings);
                case "degrees":
                    return ApplyDegreesFromRadians(functionTok, legacyQuotedStrings);
                case "polar":
                    return ApplyPolarFunction(functionTok, legacyQuotedStrings);
                case "spherical":
                    return ApplySphericalFunction(functionTok, legacyQuotedStrings);
                case "angle":
                    return ApplyAngleBetween(functionTok, legacyQuotedStrings);
                case "signed":
                    return ApplySignedAngle(functionTok, legacyQuotedStrings);
                case "saturate":
                case "sign":
                case "fract":
                    return ApplyAdvancedScalarUnary(functionTok, ParseUnaryExpression(legacyQuotedStrings));
                case "step":
                {
                    var edge = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between step arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplyStepFunction(functionTok, edge, value);
                }
                case "smoothstep":
                case "smootherstep":
                {
                    var edge0 = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", $"comma between {functionTok.Value} arguments");
                    var edge1 = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", $"comma between {functionTok.Value} arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplySmoothStepFunction(functionTok, edge0, edge1, value, functionTok.Value == "smootherstep");
                }
                case "inverse":
                {
                    ExpectWord("lerp", "P122", "Expected lerp after inverse.");
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between inverse lerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between inverse lerp arguments");
                    var value = ParseAddExpression(legacyQuotedStrings);
                    return ApplyInverseLerpFunction(functionTok, a, b, value, clamped: false);
                }
                case "remap":
                {
                    var value = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("from", "P123", "Expected from in remap expression.");
                    var inMin = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between remap input range values");
                    var inMax = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("to", "P124", "Expected to in remap expression.");
                    var outMin = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between remap output range values");
                    var outMax = ParseAddExpression(legacyQuotedStrings);
                    return ApplyRemapFunction(functionTok, value, inMin, inMax, outMin, outMax, clamped: false);
                }
                case "clamped":
                {
                    if (CurrentWordIs("inverse"))
                    {
                        Advance();
                        ExpectWord("lerp", "P122", "Expected lerp after clamped inverse.");
                        var a = ParseAddExpression(legacyQuotedStrings);
                        Expect("COMMA", "comma between clamped inverse lerp arguments");
                        var b = ParseAddExpression(legacyQuotedStrings);
                        Expect("COMMA", "comma between clamped inverse lerp arguments");
                        var value = ParseAddExpression(legacyQuotedStrings);
                        return ApplyInverseLerpFunction(functionTok, a, b, value, clamped: true);
                    }

                    if (CurrentWordIs("remap"))
                    {
                        Advance();
                        var value = ParseAddExpression(legacyQuotedStrings);
                        ExpectWord("from", "P123", "Expected from in clamped remap expression.");
                        var inMin = ParseAddExpression(legacyQuotedStrings);
                        Expect("COMMA", "comma between clamped remap input range values");
                        var inMax = ParseAddExpression(legacyQuotedStrings);
                        ExpectWord("to", "P124", "Expected to in clamped remap expression.");
                        var outMin = ParseAddExpression(legacyQuotedStrings);
                        Expect("COMMA", "comma between clamped remap output range values");
                        var outMax = ParseAddExpression(legacyQuotedStrings);
                        return ApplyRemapFunction(functionTok, value, inMin, inMax, outMin, outMax, clamped: true);
                    }

                    throw new CompileError("PARSE", "P129", Current.Line, Current.Column, "Expected inverse lerp or remap after clamped.");
                }
                case "ease":
                {
                    var mode = "";
                    if (CurrentWordIs("in"))
                    {
                        Advance();
                        if (CurrentWordIs("out"))
                        {
                            Advance();
                            mode = "in out";
                        }
                        else
                        {
                            mode = "in";
                        }
                    }
                    else if (CurrentWordIs("out"))
                    {
                        Advance();
                        mode = "out";
                    }
                    else
                    {
                        throw new CompileError("PARSE", "P127", Current.Line, Current.Column, "Expected in, out, or in out after ease.");
                    }

                    if (!CurrentWordIs("linear") && !CurrentWordIs("sine") && !CurrentWordIs("quad") && !CurrentWordIs("cubic") && !CurrentWordIs("quart") && !CurrentWordIs("quint"))
                        throw new CompileError("PARSE", "P128", Current.Line, Current.Column, "Expected ease curve linear, sine, quad, cubic, quart, or quint.");
                    var curve = Advance().Value;
                    var value = ParseUnaryExpression(legacyQuotedStrings);
                    return ApplyEaseFunction(functionTok, mode, curve, value);
                }
                case "lerp":
                {
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between lerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between lerp arguments");
                    var t = ParseAddExpression(legacyQuotedStrings);
                    return ApplyLerpFunction(functionTok, a, b, t);
                }
                case "distance":
                {
                    if (CurrentWordIs("from"))
                        return ApplyGeometryDistance(functionTok, legacyQuotedStrings);
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between distance arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    return ApplyDistanceFunction(functionTok, a, b);
                }
                case "reflect":
                {
                    var dir = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between reflect arguments");
                    var normal = ParseAddExpression(legacyQuotedStrings);
                    return ApplyReflectFunction(functionTok, dir, normal);
                }
                case "project":
                {
                    var value = ParseAddExpression(legacyQuotedStrings);
                    ExpectWord("onto", "P125", "Expected onto in project expression.");
                    var onto = ParseAddExpression(legacyQuotedStrings);
                    return ApplyProjectFunction(functionTok, value, onto);
                }
                case "clamp":
                {
                    if (CurrentWordIs("length"))
                    {
                        Advance();
                        var value = ParseAddExpression(legacyQuotedStrings);
                        ExpectWord("to", "P126", "Expected to in clamp length expression.");
                        var max = ParseAddExpression(legacyQuotedStrings);
                        return ApplyClampLengthFunction(functionTok, value, max);
                    }
                    return ParseScalarMathFunctionStartingWith(functionTok, legacyQuotedStrings);
                }
                case "component":
                    return ApplyComponentFunction(functionTok, legacyQuotedStrings);
                case "bit":
                    return ApplyBitFunction(functionTok, legacyQuotedStrings);
                case "shift":
                    return ApplyShiftFunction(functionTok, legacyQuotedStrings);
                case "quadratic":
                    return ApplyBezierFunction(functionTok, "quadratic", legacyQuotedStrings);
                case "cubic":
                    return ApplyBezierFunction(functionTok, "cubic", legacyQuotedStrings);
                case "catmull":
                    return ApplyCatmullFunction(functionTok, legacyQuotedStrings);
                case "slerp":
                {
                    var a = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between slerp arguments");
                    var b = ParseAddExpression(legacyQuotedStrings);
                    Expect("COMMA", "comma between slerp arguments");
                    var t = ParseAddExpression(legacyQuotedStrings);
                    return ApplyQuaternionSlerp(functionTok, a, b, t);
                }
                case "euler":
                    return ApplyEulerFromQuat(functionTok, legacyQuotedStrings);
                case "rotate":
                    if (CurrentWordIs("vector"))
                        return ApplyQuaternionRotateVector(functionTok, legacyQuotedStrings);
                    return ApplyMatrixFunction(functionTok);
                case "translate":
                case "scale":
                case "matmul":
                    return ApplyMatrixFunction(functionTok);
                case "compose":
                    return ApplyComposeTransform(functionTok);
                default:
                    throw new CompileError("SEMANTIC", "S120", functionTok.Line, functionTok.Column, $"Unknown advanced math function \"{functionTok.Value}\".");
            }
        }

        ExprResult ParseScalarMathFunctionStartingWith(Token functionTok, bool legacyQuotedStrings)
        {
            if (functionTok.Value == "clamp")
            {
                var value = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("between", "P120", "Expected word \"between\" in clamp expression.");
                var min = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("and", "P121", "Expected word \"and\" in clamp expression.");
                var max = ParseAddExpression(legacyQuotedStrings);
                return ApplyClampFunction(functionTok, value, min, max);
            }
            throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\".");
        }

        ExprResult ParseVectorMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            if (IsVectorBinaryFunctionName(functionTok.Value))
            {
                var left = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between vector math arguments");
                var right = ParseAddExpression(legacyQuotedStrings);
                return ApplyVectorBinaryFunction(functionTok, left, right);
            }

            if (IsVectorUnaryFunctionName(functionTok.Value))
            {
                var value = ParseUnaryExpression(legacyQuotedStrings);
                return ApplyVectorUnaryFunction(functionTok, value);
            }

            throw new CompileError("SEMANTIC", "S102", functionTok.Line, functionTok.Column, $"Unknown vector math function \"{functionTok.Value}\".");
        }

        ExprResult ParseScalarMathFunction(bool legacyQuotedStrings)
        {
            var functionTok = Advance();
            if (functionTok.Value == "clamp")
            {
                var value = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("between", "P120", "Expected word \"between\" in clamp expression.");
                var min = ParseAddExpression(legacyQuotedStrings);
                ExpectWord("and", "P121", "Expected word \"and\" in clamp expression.");
                var max = ParseAddExpression(legacyQuotedStrings);
                return ApplyClampFunction(functionTok, value, min, max);
            }

            if (IsScalarBinaryFunctionName(functionTok.Value))
            {
                var left = ParseAddExpression(legacyQuotedStrings);
                Expect("COMMA", "comma between scalar math arguments");
                var right = ParseAddExpression(legacyQuotedStrings);
                return ApplyScalarBinaryFunction(functionTok, left, right);
            }

            if (IsScalarUnaryFunctionName(functionTok.Value))
            {
                var value = ParseUnaryExpression(legacyQuotedStrings);
                return ApplyScalarUnaryFunction(functionTok, value);
            }

            throw new CompileError("SEMANTIC", "S090", functionTok.Line, functionTok.Column, $"Unknown scalar math function \"{functionTok.Value}\".");
        }

    }
}
