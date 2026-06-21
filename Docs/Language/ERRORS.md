# Arqen Errors

This file is the active diagnostic/error reference. It is generated from the current C# driver source where possible, then grouped by code.

## Code families

| Prefix | Area |
| --- | --- |
| `A` | early bootstrap/generator errors |
| `B` | backend/IR/PE/runtime lowering errors |
| `C` | codegen errors |
| `E` | expression or generic compiler errors |
| `F` | file/tooling/frontend errors |
| `L` | lexer errors |
| `P` | parser errors |
| `S` | semantic errors |
| `T` | type/literal semantic errors |
| `U` | UI/window branch errors |

## Registry

| Code | Stage(s) | Meaning / observed messages | Source examples |
| --- | --- | --- | --- |
| `A003` | M4 generator | Missing required title field | legacy bootstrap |
| `A004` | M4 generator | Missing required message field | legacy bootstrap |
| `A005` | M4 generator | Missing required exit field | legacy bootstrap |
| `B001` | BACKEND | Invalid ACTION referenced by ENTRY/FUNCTION.; Unsupported ARQIR version.; Missing supported first action. (+72 more) | Tools/M10GDriver/Backend/BackendDriver.cs:65; Tools/M10GDriver/Backend/BackendDriver.cs:76; Tools/M10GDriver/Backend/BackendDriver.cs:103 |
| `B005` | BACKEND | Mixing file I/O and window commands is not supported. | Tools/M10GDriver/Backend/BackendDriver.cs:83 |
| `B006` | BACKEND | Mixing window commands with print_stdout is not supported in M15F. | Tools/M10GDriver/Backend/WindowBackend.cs:28 |
| `B007` | BACKEND | Event block too large for short jump. | Tools/M10GDriver/Backend/WindowBackend.cs:163 |
| `L001` | LEX | Unknown character '/'. | Tools/M10GDriver/Frontend/Lexer.cs:50 |
| `L002` | LEX | Unterminated string. | Tools/M10GDriver/Frontend/Lexer.cs:62; Tools/M10GDriver/Frontend/Lexer.cs:68 |
| `L003` | LEX | Invalid decimal literal. | Tools/M10GDriver/Frontend/Lexer.cs:113 |
| `L004` | LEX | Unexpected control character. | Tools/M10GDriver/Frontend/Lexer.cs:258 |
| `P001` | PARSE | Expected title command.; Expected message command.; Expected final command. (+3 more) | Tools/M10GDriver/Parser/Parser.Core.cs:481; Tools/M10GDriver/Parser/Parser.Core.cs:483; Tools/M10GDriver/Parser/Parser.Core.cs:485 |
| `P010` | PARSE | Expected expression. | Tools/M10GDriver/Parser/Parser.Expressions.cs:245 |
| `P011` | PARSE | Expected expression after operator. | Tools/M10GDriver/Parser/Parser.Expressions.cs:64; Tools/M10GDriver/Parser/Parser.Expressions.cs:78 |
| `P012` | PARSE | Expected value after "be". | Tools/M10GDriver/Parser/Parser.Declarations.cs:20 |
| `P040` | PARSE | Expected keyword "mix" after "blend". | Tools/M10GDriver/Parser/Parser.Statements.cs:3606 |
| `P041` | PARSE | Expected keyword "to" after "blend mix". | Tools/M10GDriver/Parser/Parser.Statements.cs:3609 |
| `P042` | PARSE | Expected keyword "code" after "blend mix to". | Tools/M10GDriver/Parser/Parser.Statements.cs:3612 |
| `P043` | PARSE | Expected integer after "blend mix to code". | Tools/M10GDriver/Parser/Parser.Statements.cs:3615 |
| `P050` | PARSE | Expected keyword "title" after "set". | Tools/M10GDriver/Parser/Parser.Statements.cs:2586 |
| `P051` | PARSE | Expected keyword "to" after "set title". | Tools/M10GDriver/Parser/Parser.Statements.cs:2589 |
| `P052` | PARSE | Invalid comparison expression. Expected "is". | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:336 |
| `P053` | PARSE | Expected condition after "if". | Tools/M10GDriver/Parser/Parser.Statements.cs:2526 |
| `P054` | PARSE | Nested compile-time if statements are not supported in M13. Use runtime if for nested runtime branches. | Tools/M10GDriver/Parser/Parser.Statements.cs:313 |
| `P055` | PARSE | Unexpected else without matching if. | Tools/M10GDriver/Parser/Parser.Statements.cs:29 |
| `P056` | PARSE | Unexpected end if without matching if. | Tools/M10GDriver/Parser/Parser.Statements.cs:32 |
| `P057` | PARSE | Expected end if for runtime if.; Expected end if. | Tools/M10GDriver/Parser/Parser.Statements.cs:350; Tools/M10GDriver/Parser/Parser.Statements.cs:2555 |
| `P070` | PARSE | Expected canonical type after "define". | Tools/M10GDriver/Parser/Parser.Declarations.cs:72 |
| `P071` | PARSE | Expected keyword "called" after define type. | Tools/M10GDriver/Parser/Parser.Declarations.cs:76 |
| `P072` | PARSE | Expected quoted symbol name after "called". | Tools/M10GDriver/Parser/Parser.Declarations.cs:80 |
| `P073` | PARSE | Expected keyword "be" after symbol name. | Tools/M10GDriver/Parser/Parser.Declarations.cs:85 |
| `P074` | PARSE | Expected keyword "to" after old symbol name. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:15 |
| `P075` | PARSE | Expected keyword "to" after set target. | Tools/M10GDriver/Parser/Parser.Statements.cs:2756 |
| `P076` | PARSE | Expected keyword "to" after add expression. | Tools/M10GDriver/Parser/Parser.Statements.cs:2771 |
| `P077` | PARSE | Expected keyword "from" after remove expression. | Tools/M10GDriver/Parser/Parser.Statements.cs:2785 |
| `P078` | PARSE | Expected keyword "by" after multiply target. | Tools/M10GDriver/Parser/Parser.Statements.cs:2799 |
| `P079` | PARSE | Expected keyword "by" after divide target. | Tools/M10GDriver/Parser/Parser.Statements.cs:2811 |
| `P080` | PARSE | Expected end while for runtime while. | Tools/M10GDriver/Parser/Parser.Statements.cs:594 |
| `P081` | PARSE | Unexpected end while without matching while. | Tools/M10GDriver/Parser/Parser.Statements.cs:35 |
| `P082` | PARSE | while inside compile-time if is not supported in M14C. | Tools/M10GDriver/Parser/Parser.Statements.cs:2429 |
| `P090` | PARSE | Expected keyword "called" after define function. | Tools/M10GDriver/Parser/Parser.Statements.cs:2927 |
| `P091` | PARSE | Unexpected end function without matching function. | Tools/M10GDriver/Parser/Parser.Statements.cs:38 |
| `P093` | PARSE | Expected keyword "function" after call. | Tools/M10GDriver/Parser/Parser.Statements.cs:3265 |
| `P100` | PARSE | file I/O inside compile-time if is not supported in M15C.; Expected keyword "file" after write. | Tools/M10GDriver/Parser/Parser.Statements.cs:2436; Tools/M10GDriver/Parser/Parser.Statements.cs:2448; Tools/M10GDriver/Parser/Parser.Statements.cs:2661 |
| `P101` | PARSE | Expected keyword "with" after file path. | Tools/M10GDriver/Parser/Parser.Statements.cs:2665 |
| `P102` | PARSE | Expected keyword "to" after add value. | Tools/M10GDriver/Parser/Parser.Statements.cs:2678 |
| `P103` | PARSE | Expected keyword "file" after add value to. | Tools/M10GDriver/Parser/Parser.Statements.cs:2681 |
| `P104` | PARSE | Expected keyword "file" after load. | Tools/M10GDriver/Parser/Parser.Statements.cs:2693 |
| `P105` | PARSE | Expected keyword "to" after load file path. | Tools/M10GDriver/Parser/Parser.Statements.cs:2697 |
| `P106` | PARSE | Expected file value. | Tools/M10GDriver/Parser/Parser.Statements.cs:2727 |
| `P107` | PARSE | Expected integer for resolution width. | Tools/M10GDriver/Parser/Parser.Statements.cs:136 |
| `P108` | PARSE | Expected 'x' between resolution dimensions. | Tools/M10GDriver/Parser/Parser.Statements.cs:139 |
| `P109` | PARSE | Expected integer for resolution height. | Tools/M10GDriver/Parser/Parser.Statements.cs:152 |
| `P110` | PARSE | Expected keyword "arg" after "command".; Expected boolean for resizable value. | Tools/M10GDriver/Parser/Parser.Declarations.cs:169; Tools/M10GDriver/Parser/Parser.Statements.cs:175 |
| `P111` | PARSE | Expected integer command arg index. | Tools/M10GDriver/Parser/Parser.Declarations.cs:191; Tools/M10GDriver/Parser/Parser.Declarations.cs:196 |
| `P113` | PARSE | Unexpected tokens after command arg index. | Tools/M10GDriver/Parser/Parser.Declarations.cs:200 |
| `P114` | PARSE | Unexpected tokens after command arg count. | Tools/M10GDriver/Parser/Parser.Declarations.cs:178 |
| `P119` | PARSE | Runtime define supports int, bool, and string slots.; Unsupported runtime slot type. | Tools/M10GDriver/Parser/Parser.Declarations.cs:106; Tools/M10GDriver/Parser/Parser.Declarations.cs:123 |
| `P121` | PARSE | Runtime int comparisons support "is", "is not", "equals", "less than", and "greater than". | Tools/M10GDriver/Parser/Parser.Statements.cs:876 |
| `P123` | PARSE | Expected runtime set type: int, bool, or string.; Unsupported runtime set type. | Tools/M10GDriver/Parser/Parser.Statements.cs:609; Tools/M10GDriver/Parser/Parser.Statements.cs:754 |
| `P126` | PARSE | Runtime bool comparisons support "is true", "is false", "is not true", and "equals false". | Tools/M10GDriver/Parser/Parser.Statements.cs:902 |
| `P127` | PARSE | Expected in, out, or in out after ease. | Tools/M10GDriver/Parser/Parser.AdvancedMath.cs:129 |
| `P128` | PARSE | Expected ease curve linear, sine, quad, cubic, quart, or quint.; Runtime string comparisons support equals, is, is not, and contains with runtime string operands. | Tools/M10GDriver/Parser/Parser.AdvancedMath.cs:133; Tools/M10GDriver/Parser/Parser.Statements.cs:933 |
| `P129` | PARSE | Expected inverse lerp or remap after clamped. | Tools/M10GDriver/Parser/Parser.AdvancedMath.cs:104 |
| `P130` | PARSE | Expected vector component after comma. | Tools/M10GDriver/Parser/Parser.Expressions.cs:155 |
| `P140` | PARSE | Expected color literal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:600 |
| `P141` | PARSE | Expected runtime return type: int, bool, string, or enum.; Unsupported runtime return type. | Tools/M10GDriver/Parser/Parser.Statements.cs:2328; Tools/M10GDriver/Parser/Parser.Statements.cs:2335 |
| `P142` | PARSE | Expected function parameter type: runtime int, runtime bool, runtime string, runtime enum, runtime <type> array, or runtime record. | Tools/M10GDriver/Parser/Parser.Statements.cs:3214 |
| `P143` | PARSE | Expected runtime argument type: int, bool, string, enum, <type> array, or record.; Unsupported runtime function argument type.; Function arguments require int, bool, string, runtime <type>, runtime enum, runtime <type> array, or runtime record. | Tools/M10GDriver/Parser/Parser.Statements.cs:3333; Tools/M10GDriver/Parser/Parser.Statements.cs:3348; Tools/M10GDriver/Parser/Parser.Statements.cs:3377 |
| `P144` | PARSE | Local runtime declarations support int, bool, string slots, arrays, records, and enums.; Unsupported local runtime slot type. | Tools/M10GDriver/Parser/Parser.Statements.cs:1228; Tools/M10GDriver/Parser/Parser.Statements.cs:1257 |
| `P150` | PARSE | Expected runtime array type: int, bool, or string. | Tools/M10GDriver/Parser/Parser.Statements.cs:1449 |
| `P152` | PARSE | Expected runtime array set type: int, bool, or string.; Unsupported runtime array set type. | Tools/M10GDriver/Parser/Parser.Statements.cs:1482; Tools/M10GDriver/Parser/Parser.Statements.cs:1494 |
| `P154` | PARSE | Array length supports runtime int/bool/string arrays and runtime enum arrays. | Tools/M10GDriver/Parser/Parser.Statements.cs:1538 |
| `P158` | PARSE | fill runtime array supports int, bool, and string arrays. | Tools/M10GDriver/Parser/Parser.Statements.cs:1550 |
| `P159` | PARSE | copy runtime array supports int, bool, and string arrays. | Tools/M10GDriver/Parser/Parser.Statements.cs:1571 |
| `P160` | PARSE | Record field type must be runtime int, bool, string, or enum. | Tools/M10GDriver/Parser/Parser.Statements.cs:2102 |
| `P164` | PARSE | Unsupported runtime typed operand type. | Tools/M10GDriver/Parser/Parser.Statements.cs:1024 |
| `P168` | PARSE | Expected rect, circle, segment, sphere, or aabb after closest point on. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:306 |
| `P176` | PARSE | Runtime enum comparisons support is, is not, and equals. | Tools/M10GDriver/Parser/Parser.Statements.cs:1894 |
| `P177` | PARSE | runtime switch supports enum and int in M57/M58. | Tools/M10GDriver/Parser/Parser.Statements.cs:376 |
| `P180` | PARSE | Expected case, default, or end switch in runtime switch enum.; Expected case, default, or end switch in runtime switch int. | Tools/M10GDriver/Parser/Parser.Statements.cs:482; Tools/M10GDriver/Parser/Parser.Statements.cs:560 |
| `P182` | PARSE | Expected between, int, vector2, or vector3 after random. | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:177 |
| `P202` | PARSE | Expected ':' after style property name.; Expected style property name. | Tools/M10GDriver/Parser/Parser.Style.cs:514; Tools/M10GDriver/Parser/Parser.Style.cs:516; Tools/M10GDriver/Parser/Parser.Style.cs:521 |
| `P210` | PARSE | Expected component sum, average, min, max, or product. | Tools/M10GDriver/Parser/Parser.Operations.cs:404 |
| `P211` | PARSE | Expected bit and, bit or, bit xor, or bit not. | Tools/M10GDriver/Parser/Parser.Operations.cs:425 |
| `P212` | PARSE | Expected shift left or shift right. | Tools/M10GDriver/Parser/Parser.Operations.cs:453 |
| `P217` | PARSE | Expected line or segment in geometry distance expression. | Tools/M10GDriver/Parser/Parser.Operations.cs:475 |
| `P221` | PARSE | Expected point or tangent after bezier. | Tools/M10GDriver/Parser/Parser.Operations.cs:500 |
| `P230` | PARSE | Expected UI object type. | Tools/M10GDriver/Parser/Parser.Ui.cs:89 |
| `P231` | PARSE | Expected UI property name. | Tools/M10GDriver/Parser/Parser.Ui.cs:151 |
| `P240` | PARSE | Expected end layout.; Expected x or y after offset. | Tools/M10GDriver/Parser/Parser.Layout.cs:155; Tools/M10GDriver/Parser/Parser.Layout.cs:183 |
| `P250` | PARSE | Expected UI event name after when. | Tools/M10GDriver/Parser/Parser.UiFinal.cs:164 |
| `P270` | PARSE | Expected UI state property. | Tools/M10GDriver/Parser/Parser.UiFinal.cs:308 |
| `P280` | PARSE | Expected end shader.; Expected UI resource type. | Tools/M10GDriver/Parser/Parser.Dx12.cs:180; Tools/M10GDriver/Parser/Parser.UiFinal.cs:358 |
| `P281` | PARSE | Expected UI resource property. | Tools/M10GDriver/Parser/Parser.UiFinal.cs:420 |
| `P283` | PARSE | Expected end pipeline. | Tools/M10GDriver/Parser/Parser.Dx12.cs:258 |
| `P287` | PARSE | Expected end vertex buffer. | Tools/M10GDriver/Parser/Parser.Dx12.cs:402 |
| `P294` | PARSE | Expected end constant buffer. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1593 |
| `P300` | PARSE | Expected end color sequence. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1687 |
| `P340` | PARSE | Expected object or camera after set position of.; Expected DX12 transform/camera statement. | Tools/M10GDriver/Parser/Parser.Dx12.cs:832; Tools/M10GDriver/Parser/Parser.Dx12.cs:1018 |
| `P341` | PARSE | Expected x/y/z for object rotation or of object/camera for full rotation. | Tools/M10GDriver/Parser/Parser.Dx12.cs:878 |
| `P356` | PARSE | Expected plane after near/far.; Expected camera after plane of. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1001; Tools/M10GDriver/Parser/Parser.Dx12.cs:1003 |
| `P360` | PARSE | Expected DX12 keyboard input action. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1463 |
| `P383` | PARSE | Expected DX12 mouse input action. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1344 |
| `P385` | PARSE | Expected DX12 mouse button action. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1341 |
| `S002` | SEMANTIC | Invalid variable name. | Tools/M10GDriver/Parser/Parser.Declarations.cs:14 |
| `S003` | SEMANTIC | Unknown variable reference in let value. | Tools/M10GDriver/Parser/Parser.Declarations.cs:44 |
| `S011` | SEMANTIC | Type mismatch in expression. | Tools/M10GDriver/Parser/Parser.Operations.cs:30 |
| `S013` | SEMANTIC | Only exit 0 is supported in M10G. | Tools/M10GDriver/Parser/Parser.Statements.cs:3597 |
| `S021` | SEMANTIC | blend mix to code only supports 0 currently. | Tools/M10GDriver/Parser/Parser.Statements.cs:3618 |
| `S024` | SEMANTIC | DX12 renderer definitions inside compile-time if are not supported in M20B.; DX12 renderer parenting inside compile-time if is not supported in M20B.; DX12 frame commands inside compile-time if are not supported in M20G. (+42 more) | Tools/M10GDriver/Parser/Parser.Dx12.cs:13; Tools/M10GDriver/Parser/Parser.Dx12.cs:36; Tools/M10GDriver/Parser/Parser.Dx12.cs:64 |
| `S030` | SEMANTIC | define string requires string literal syntax: string "...". | Tools/M10GDriver/Parser/Parser.Declarations.cs:211 |
| `S031` | SEMANTIC | define int requires an integer literal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:218 |
| `S032` | SEMANTIC | define bool requires true or false. | Tools/M10GDriver/Parser/Parser.Declarations.cs:241 |
| `S033` | SEMANTIC | define var requires string, int, bool, vector, matrix, transform, quaternion, geometry, complex, color, or angle literal value. | Tools/M10GDriver/Parser/Parser.Declarations.cs:355 |
| `S037` | SEMANTIC | define float requires a numeric literal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:225 |
| `S038` | SEMANTIC | define double requires a numeric literal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:233 |
| `S040` | SEMANTIC | Condition must evaluate to bool. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:334 |
| `S041` | SEMANTIC | not requires a bool operand. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:378 |
| `S042` | SEMANTIC | Numeric comparison requires numeric operands. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:413 |
| `S043` | SEMANTIC | Unary minus requires numeric or complex operand. | Tools/M10GDriver/Parser/Parser.Expressions.cs:109 |
| `S044` | SEMANTIC | Numeric expression requires numeric operands.; Unknown numeric operator.; Quick math update requires numeric operands. | Tools/M10GDriver/Parser/Parser.Operations.cs:109; Tools/M10GDriver/Parser/Parser.Operations.cs:128; Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:154 |
| `S045` | SEMANTIC | Modulo only supports integer operands. | Tools/M10GDriver/Parser/Parser.Operations.cs:112 |
| `S046` | SEMANTIC | Division by zero. | Tools/M10GDriver/Parser/Parser.Operations.cs:92; Tools/M10GDriver/Parser/Parser.Operations.cs:117 |
| `S047` | SEMANTIC | while iteration guard exceeded. | Tools/M10GDriver/Parser/Parser.Statements.cs:2914 |
| `S048` | SEMANTIC | const function is not supported. | Tools/M10GDriver/Parser/Parser.Statements.cs:2924 |
| `S052` | SEMANTIC | Nested function definitions are not supported in M39. | Tools/M10GDriver/Parser/Parser.Statements.cs:2920 |
| `S062` | SEMANTIC | File path cannot be empty. | Tools/M10GDriver/Parser/Parser.Statements.cs:2720 |
| `S070` | SEMANTIC | command arg count must be defined as int.; command arg index must be defined as string.; Window resolution dimensions must be positive integers. | Tools/M10GDriver/Parser/Parser.Declarations.cs:175; Tools/M10GDriver/Parser/Parser.Declarations.cs:185; Tools/M10GDriver/Parser/Parser.Statements.cs:157 |
| `S071` | SEMANTIC | const command arg targets are not supported. | Tools/M10GDriver/Parser/Parser.Declarations.cs:165 |
| `S072` | SEMANTIC | command arg index cannot be negative. | Tools/M10GDriver/Parser/Parser.Declarations.cs:190; Tools/M10GDriver/Parser/Parser.Declarations.cs:198 |
| `S073` | SEMANTIC | Only one window is supported in M15F. | Tools/M10GDriver/Parser/Parser.Statements.cs:87 |
| `S075` | SEMANTIC | Print is not supported with window actions. | Tools/M10GDriver/Parser/Parser.Statements.cs:77; Tools/M10GDriver/Parser/Parser.Statements.cs:269 |
| `S090` | SEMANTIC | clamp requires numeric operands. | Tools/M10GDriver/Parser/Parser.Operations.cs:201 |
| `S091` | SEMANTIC | sqrt requires a non-negative operand. | Tools/M10GDriver/Parser/Parser.Operations.cs:146 |
| `S092` | SEMANTIC | log requires an operand greater than 0.; log10 requires an operand greater than 0.; log2 requires an operand greater than 0. | Tools/M10GDriver/Parser/Parser.Operations.cs:163; Tools/M10GDriver/Parser/Parser.Operations.cs:164; Tools/M10GDriver/Parser/Parser.Operations.cs:165 |
| `S093` | SEMANTIC | clamp minimum cannot be greater than maximum. | Tools/M10GDriver/Parser/Parser.Operations.cs:206 |
| `S094` | SEMANTIC | Math result must be finite.; Integer math result is outside the supported range. | Tools/M10GDriver/Parser/Parser.TypeSystem.cs:446; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:458 |
| `S095` | SEMANTIC | asin requires operand between -1 and 1.; acos requires operand between -1 and 1.; acosh requires operand greater than or equal to 1. (+1 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:154; Tools/M10GDriver/Parser/Parser.Operations.cs:155; Tools/M10GDriver/Parser/Parser.Operations.cs:161 |
| `S102` | SEMANTIC | Vector division requires vector / numeric scalar.; Expected vector value. | Tools/M10GDriver/Parser/Parser.Operations.cs:89; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:32 |
| `S103` | SEMANTIC | normalize requires a non-zero vector. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:39 |
| `S104` | SEMANTIC | dot requires matching vector dimensions. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:52 |
| `S105` | SEMANTIC | cross requires vec3 operands. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:66 |
| `S106` | SEMANTIC | Vector literal cannot be empty.; Vector literal must have 2, 3, or 4 components. | Tools/M10GDriver/Parser/Parser.Expressions.cs:142; Tools/M10GDriver/Parser/Parser.Expressions.cs:165 |
| `S107` | SEMANTIC | Vector literal components must be numeric. | Tools/M10GDriver/Parser/Parser.Expressions.cs:148 |
| `S108` | SEMANTIC | Component assignment requires vector symbol. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:126 |
| `S109` | SEMANTIC | Vector component assignment requires numeric value. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:128 |
| `S110` | SEMANTIC | Color hex literal must be #RRGGBB or #RRGGBBAA.; Color hex literal contains non-hex characters. | Tools/M10GDriver/Parser/Parser.Declarations.cs:626; Tools/M10GDriver/Parser/Parser.Declarations.cs:629 |
| `S111` | SEMANTIC | define angle requires numeric literal followed by deg or rad. | Tools/M10GDriver/Parser/Parser.Declarations.cs:300 |
| `S120` | SEMANTIC | step requires numeric operands.; inverse lerp requires numeric operands.; remap requires numeric operands. (+1 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:234; Tools/M10GDriver/Parser/Parser.Operations.cs:255; Tools/M10GDriver/Parser/Parser.Operations.cs:270 |
| `S121` | SEMANTIC | inverse lerp range cannot be zero.; remap input range cannot be zero. | Tools/M10GDriver/Parser/Parser.Operations.cs:259; Tools/M10GDriver/Parser/Parser.Operations.cs:274 |
| `S122` | SEMANTIC | lerp requires matching numeric or vector endpoints.; distance requires matching vector operands.; reflect requires matching vector operands. (+2 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:341; Tools/M10GDriver/Parser/Parser.Operations.cs:347; Tools/M10GDriver/Parser/Parser.Operations.cs:357 |
| `S123` | SEMANTIC | project target vector cannot be zero. | Tools/M10GDriver/Parser/Parser.Operations.cs:373 |
| `S124` | SEMANTIC | clamp length max cannot be negative. | Tools/M10GDriver/Parser/Parser.Operations.cs:385 |
| `S125` | SEMANTIC | ease requires a numeric factor.; ease factor must be between 0 and 1.; Unknown ease direction. | Tools/M10GDriver/Parser/Parser.Operations.cs:286; Tools/M10GDriver/Parser/Parser.Operations.cs:290; Tools/M10GDriver/Parser/Parser.Operations.cs:301 |
| `S130` | SEMANTIC | matmul requires matrix or transform operands.; Expected mat4 or transform value.; mat4 value must have 16 components. | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:43; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:117; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:123 |
| `S131` | SEMANTIC | translate requires vec3 operand.; scale requires vec3 operand.; translate requires vec3 value. (+1 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:17; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:24; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:378 |
| `S132` | SEMANTIC | rotate axis must be x, y, or z.; rotate angle must be numeric or angle.; compose transform rotation axis must be x, y, or z. (+1 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:30; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:34; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:75 |
| `S133` | SEMANTIC | transform point/direction requires mat4 or transform operand.; transform point/direction value must be vec3.; Expected point or direction after transform. (+1 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:59; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:61; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:65 |
| `S134` | SEMANTIC | compose transform requires vec3 position and vec3 scale. | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:81 |
| `S135` | SEMANTIC | Runtime int math requires an integer literal/expression or runtime int slot.; Runtime int math literal must fit i32. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:174; Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:178 |
| `S136` | SEMANTIC | M34D runtime int math supports add/remove only. | Tools/M10GDriver/Parser/Parser.SymbolsFlow.cs:165 |
| `S138` | SEMANTIC | break is only supported inside runtime while blocks. | Tools/M10GDriver/Parser/Parser.Statements.cs:1190 |
| `S139` | SEMANTIC | continue is only supported inside runtime while blocks. | Tools/M10GDriver/Parser/Parser.Statements.cs:1200 |
| `S148` | SEMANTIC | Runtime string comparisons support equality/contains only in M37. | Tools/M10GDriver/Parser/Parser.Statements.cs:937 |
| `S149` | SEMANTIC | contains ignoring case is reserved; M37 supports ignoring case for equality only. | Tools/M10GDriver/Parser/Parser.Statements.cs:946 |
| `S150` | SEMANTIC | Quaternion axis must be vec3.; Expected quaternion value. | Tools/M10GDriver/Parser/Parser.Declarations.cs:371; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:133; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:147 |
| `S151` | SEMANTIC | Quaternion angle must be numeric or angle. | Tools/M10GDriver/Parser/Parser.Declarations.cs:375 |
| `S152` | SEMANTIC | Quaternion cannot have zero length.; Quaternion axis must be non-zero.; Quaternion slerp produced zero length result. | Tools/M10GDriver/Parser/Parser.TypeSystem.cs:137; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:150; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:196 |
| `S153` | SEMANTIC | slerp requires quaternion operands.; slerp t must be numeric. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:96; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:98 |
| `S154` | SEMANTIC | rotate vector requires vec3 value.; rotate vector requires quaternion operand.; rotate vector requires vec3. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:84; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:88; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:172 |
| `S155` | SEMANTIC | euler from quat requires quaternion operand. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:109 |
| `S159` | SEMANTIC | return is only supported inside function bodies. | Tools/M10GDriver/Parser/Parser.Statements.cs:2295 |
| `S160` | SEMANTIC | rect origin must be vec2.; rect size must be vec2.; return values require int, bool, string, enum, runtime <type>, or runtime enum in M59. (+2 more) | Tools/M10GDriver/Parser/Parser.Declarations.cs:385; Tools/M10GDriver/Parser/Parser.Declarations.cs:389; Tools/M10GDriver/Parser/Parser.Statements.cs:2377 |
| `S161` | SEMANTIC | rect size cannot be negative. | Tools/M10GDriver/Parser/Parser.Declarations.cs:392 |
| `S162` | SEMANTIC | circle center must be vec2.; circle radius must be numeric.; Expected circle value. (+1 more) | Tools/M10GDriver/Parser/Parser.Declarations.cs:402; Tools/M10GDriver/Parser/Parser.Declarations.cs:406; Tools/M10GDriver/Parser/Parser.TypeSystem.cs:268 |
| `S163` | SEMANTIC | circle radius cannot be negative. | Tools/M10GDriver/Parser/Parser.Declarations.cs:409 |
| `S164` | SEMANTIC | point inside requires vec2 point.; point inside requires rect or circle shape. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:151; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:159 |
| `S165` | SEMANTIC | rect intersects requires rect operand.; rect intersects requires rect or circle operand. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:168; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:175 |
| `S166` | SEMANTIC | closest point on rect requires rect operand.; closest point target must be vec2.; closest point on circle requires circle operand. (+5 more) | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:251; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:255; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:263 |
| `S167` | SEMANTIC | int function arguments use int literals; use runtime int for slot arguments.; bool function arguments use bool literals; use runtime bool for slot arguments. | Tools/M10GDriver/Parser/Parser.Statements.cs:3360; Tools/M10GDriver/Parser/Parser.Statements.cs:3368 |
| `S170` | SEMANTIC | define complex requires a complex expression.; Complex real part must be numeric.; Complex imaginary part must be numeric. (+4 more) | Tools/M10GDriver/Parser/Parser.Declarations.cs:528; Tools/M10GDriver/Parser/Parser.Declarations.cs:536; Tools/M10GDriver/Parser/Parser.Declarations.cs:540 |
| `S171` | SEMANTIC | Complex operation requires complex or numeric operands. | Tools/M10GDriver/Parser/Parser.Operations.cs:36 |
| `S172` | SEMANTIC | Complex division by zero. | Tools/M10GDriver/Parser/Parser.Operations.cs:54 |
| `S180` | SEMANTIC | random between requires numeric range values.; random minimum cannot be greater than maximum.; random int between requires numeric range values. (+17 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:97; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:103; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:116 |
| `S181` | SEMANTIC | noise seed must be numeric.; noise seed must be a non-negative integer within uint range.; noise at requires vec2 or vec3 coordinates. (+1 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:190; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:193; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:198 |
| `S182` | SEMANTIC | radians from degrees requires numeric degrees.; degrees from radians requires numeric or angle radians.; polar radius must be numeric. (+9 more) | Tools/M10GDriver/Parser/Parser.MathFunctions.cs:244; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:255; Tools/M10GDriver/Parser/Parser.MathFunctions.cs:267 |
| `S186` | SEMANTIC | define local runtime array is only supported inside function bodies in M49. | Tools/M10GDriver/Parser/Parser.Statements.cs:1414 |
| `S190` | SEMANTIC | segment start must be vec2.; segment end must be vec2. | Tools/M10GDriver/Parser/Parser.Declarations.cs:419; Tools/M10GDriver/Parser/Parser.Declarations.cs:423 |
| `S191` | SEMANTIC | segment endpoints cannot be equal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:427 |
| `S192` | SEMANTIC | line start must be vec2.; line end must be vec2. | Tools/M10GDriver/Parser/Parser.Declarations.cs:437; Tools/M10GDriver/Parser/Parser.Declarations.cs:441 |
| `S193` | SEMANTIC | line points cannot be equal. | Tools/M10GDriver/Parser/Parser.Declarations.cs:445 |
| `S194` | SEMANTIC | ray origin must be vec3.; ray direction must be vec3. | Tools/M10GDriver/Parser/Parser.Declarations.cs:455; Tools/M10GDriver/Parser/Parser.Declarations.cs:459 |
| `S195` | SEMANTIC | ray direction cannot be zero. | Tools/M10GDriver/Parser/Parser.Declarations.cs:463 |
| `S196` | SEMANTIC | sphere center must be vec3.; sphere radius must be numeric. | Tools/M10GDriver/Parser/Parser.Declarations.cs:474; Tools/M10GDriver/Parser/Parser.Declarations.cs:478 |
| `S197` | SEMANTIC | sphere radius cannot be negative. | Tools/M10GDriver/Parser/Parser.Declarations.cs:481 |
| `S198` | SEMANTIC | aabb center must be vec3.; aabb size must be vec3. | Tools/M10GDriver/Parser/Parser.Declarations.cs:491; Tools/M10GDriver/Parser/Parser.Declarations.cs:495 |
| `S199` | SEMANTIC | aabb size cannot be negative. | Tools/M10GDriver/Parser/Parser.Declarations.cs:498 |
| `S200` | SEMANTIC | plane normal must be vec3.; plane distance must be numeric. | Tools/M10GDriver/Parser/Parser.Declarations.cs:508; Tools/M10GDriver/Parser/Parser.Declarations.cs:512 |
| `S201` | SEMANTIC | plane normal cannot be zero. | Tools/M10GDriver/Parser/Parser.Declarations.cs:516 |
| `S202` | SEMANTIC | segment intersects requires segment operand.; segment intersects requires another segment.; define local runtime record is only supported inside function bodies in M53. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:184; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:188; Tools/M10GDriver/Parser/Parser.Statements.cs:1385 |
| `S203` | SEMANTIC | ray intersects requires ray operand.; ray intersects requires sphere, aabb, or plane target. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:197; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:205 |
| `S204` | SEMANTIC | sphere intersects requires sphere operand.; sphere intersects requires sphere or aabb target. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:214; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:221 |
| `S205` | SEMANTIC | aabb intersects requires aabb operand.; aabb intersects requires aabb or sphere target. | Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:230; Tools/M10GDriver/Parser/Parser.GeometryFunctions.cs:237 |
| `S206` | SEMANTIC | Font weight must be a word or a numeric weight between 100 and 900 in steps of 100. | Tools/M10GDriver/Parser/Parser.Style.cs:742 |
| `S209` | SEMANTIC | Style opacity must be between 0 and 1. | Tools/M10GDriver/Parser/Parser.Style.cs:618 |
| `S210` | SEMANTIC | component aggregate requires vector operand.; Unknown component aggregate. | Tools/M10GDriver/Parser/Parser.Operations.cs:408; Tools/M10GDriver/Parser/Parser.Operations.cs:417 |
| `S211` | SEMANTIC | Unknown bit operation.; Font name cannot be empty. | Tools/M10GDriver/Parser/Parser.Operations.cs:444; Tools/M10GDriver/Parser/Parser.Style.cs:729 |
| `S212` | SEMANTIC | shift amount must be between 0 and 62. | Tools/M10GDriver/Parser/Parser.Operations.cs:461 |
| `S213` | SEMANTIC | distance from point requires vec2 point.; distance to line requires line operand.; distance to segment requires segment operand. (+1 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:472; Tools/M10GDriver/Parser/Parser.Operations.cs:483; Tools/M10GDriver/Parser/Parser.Operations.cs:489 |
| `S216` | SEMANTIC | Enum values cannot be empty.; Enum types require at least one value. | Tools/M10GDriver/Parser/Parser.Statements.cs:1735; Tools/M10GDriver/Parser/Parser.Statements.cs:1754 |
| `S219` | SEMANTIC | runtime switch enum requires at least one case or default.; runtime switch int requires at least one case or default. | Tools/M10GDriver/Parser/Parser.Statements.cs:486; Tools/M10GDriver/Parser/Parser.Statements.cs:564 |
| `S220` | SEMANTIC | bezier t must be numeric.; bezier t must be between 0 and 1.; curve points must be matching vectors. (+2 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:516; Tools/M10GDriver/Parser/Parser.Operations.cs:519; Tools/M10GDriver/Parser/Parser.Operations.cs:556 |
| `S221` | SEMANTIC | catmull t must be numeric.; catmull t must be between 0 and 1.; runtime switch enum case cannot appear after default. (+1 more) | Tools/M10GDriver/Parser/Parser.Operations.cs:538; Tools/M10GDriver/Parser/Parser.Operations.cs:541; Tools/M10GDriver/Parser/Parser.Statements.cs:449 |
| `S226` | SEMANTIC | define local runtime enum is only supported inside function bodies in M61. | Tools/M10GDriver/Parser/Parser.Statements.cs:1308 |
| `S229` | SEMANTIC | define local runtime enum array is only supported inside function bodies in M61. | Tools/M10GDriver/Parser/Parser.Statements.cs:1347 |
| `S230` | SEMANTIC | UI object name cannot be empty. | Tools/M10GDriver/Parser/Parser.Ui.cs:97 |
| `S233` | SEMANTIC | placeholder is only supported on input field.; range is only supported on slider.; checked is only supported on checkbox. (+1 more) | Tools/M10GDriver/Parser/Parser.Ui.cs:188; Tools/M10GDriver/Parser/Parser.Ui.cs:197; Tools/M10GDriver/Parser/Parser.Ui.cs:241 |
| `S234` | SEMANTIC | Slider range minimum must be numeric.; Slider range maximum must be numeric.; Slider value must be numeric. | Tools/M10GDriver/Parser/Parser.Ui.cs:201; Tools/M10GDriver/Parser/Parser.Ui.cs:206; Tools/M10GDriver/Parser/Parser.Ui.cs:223 |
| `S235` | SEMANTIC | Slider range minimum cannot be greater than maximum. | Tools/M10GDriver/Parser/Parser.Ui.cs:212 |
| `S237` | SEMANTIC | checked requires a boolean value. | Tools/M10GDriver/Parser/Parser.Ui.cs:244 |
| `S241` | SEMANTIC | Unknown layout property. | Tools/M10GDriver/Parser/Parser.Layout.cs:185 |
| `S246` | SEMANTIC | UI object cannot be parented to itself.; UI parent relationship would create a cycle.; UI object cannot be docked to itself. (+1 more) | Tools/M10GDriver/Parser/Parser.Layout.cs:80; Tools/M10GDriver/Parser/Parser.Layout.cs:84; Tools/M10GDriver/Parser/Parser.Layout.cs:110 |
| `S254` | SEMANTIC | Nested UI event blocks are not supported in M19E. | Tools/M10GDriver/Parser/Parser.UiFinal.cs:210 |
| `S260` | SEMANTIC | DX12 renderer name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:23 |
| `S264` | SEMANTIC | DX12 renderer cannot be parented to itself. | Tools/M10GDriver/Parser/Parser.Dx12.cs:53 |
| `S265` | SEMANTIC | DX12 renderer styles only support the default state in M20C. | Tools/M10GDriver/Parser/Parser.Style.cs:380 |
| `S280` | SEMANTIC | DX12 shader name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:168 |
| `S281` | SEMANTIC | Vertex shader source file cannot be empty.; Pixel shader source file cannot be empty.; UI resource name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:191; Tools/M10GDriver/Parser/Parser.Dx12.cs:205; Tools/M10GDriver/Parser/Parser.UiFinal.cs:368 |
| `S282` | SEMANTIC | Unsupported DX12 shader block property. Expected vertex source file or pixel source file.; UI resource path cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:212; Tools/M10GDriver/Parser/Parser.UiFinal.cs:372 |
| `S283` | SEMANTIC | DX12 pipeline name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:245 |
| `S284` | SEMANTIC | Unsupported DX12 pipeline block property. Expected renderer, shader, or topology.; Unsupported DX12 pipeline topology. Supported in M21B: triangle list. | Tools/M10GDriver/Parser/Parser.Dx12.cs:298; Tools/M10GDriver/Parser/Parser.Dx12.cs:332 |
| `S287` | SEMANTIC | DX12 vertex buffer name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:391 |
| `S288` | SEMANTIC | DX12 vertex position must be a vec3.; DX12 vertex color must be a vec4.; DX12 vertex color components must be between 0 and 1. | Tools/M10GDriver/Parser/Parser.Dx12.cs:409; Tools/M10GDriver/Parser/Parser.Dx12.cs:415; Tools/M10GDriver/Parser/Parser.Dx12.cs:419 |
| `S293` | SEMANTIC | DX12 draw vertex count must be a positive integer.; DX12 draw requires at least 3 vertices. | Tools/M10GDriver/Parser/Parser.Dx12.cs:500; Tools/M10GDriver/Parser/Parser.Dx12.cs:751 |
| `S294` | SEMANTIC | DX12 constant buffer name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1582 |
| `S295` | SEMANTIC | M21G supports only color tint in DX12 constant buffers.; DX12 constant buffer tint requires a color value.; Unsupported DX12 constant buffer field. Supported in M21G: color tint. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1601; Tools/M10GDriver/Parser/Parser.Dx12.cs:1608; Tools/M10GDriver/Parser/Parser.Dx12.cs:1615 |
| `S300` | SEMANTIC | DX12 color sequence name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1676 |
| `S301` | SEMANTIC | DX12 color sequence entries must be color literals, not vectors.; DX12 color sequence entries must be color literals. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1691; Tools/M10GDriver/Parser/Parser.Dx12.cs:1695 |
| `S303` | SEMANTIC | DX12 animate color target must be ConstantBuffer.field, for example TriangleParams.tint. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1740 |
| `S305` | SEMANTIC | DX12 color animation interval must be a positive integer. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1748 |
| `S320` | SEMANTIC | DX12 object name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:589 |
| `S325` | SEMANTIC | DX12 object draw count must be at least 3 vertices. | Tools/M10GDriver/Parser/Parser.Dx12.cs:641 |
| `S340` | SEMANTIC | DX12 object position must be a vec3. | Tools/M10GDriver/Parser/Parser.Dx12.cs:814 |
| `S342` | SEMANTIC | DX12 object scale must be a vec3.; DX12 object scale components must be non-zero. | Tools/M10GDriver/Parser/Parser.Dx12.cs:948; Tools/M10GDriver/Parser/Parser.Dx12.cs:951 |
| `S348` | SEMANTIC | DX12 camera name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1061 |
| `S350` | SEMANTIC | DX12 camera position must be a vec3. | Tools/M10GDriver/Parser/Parser.Dx12.cs:827 |
| `S351` | SEMANTIC | DX12 camera zoom must be numeric.; DX12 camera zoom must be positive. | Tools/M10GDriver/Parser/Parser.Dx12.cs:967; Tools/M10GDriver/Parser/Parser.Dx12.cs:970 |
| `S352` | SEMANTIC | DX12 camera projection must be orthographic or perspective. | Tools/M10GDriver/Parser/Parser.Dx12.cs:795; Tools/M10GDriver/Parser/Parser.Dx12.cs:1102 |
| `S353` | SEMANTIC | DX12 camera rotation must be a vec3 of pitch/yaw/roll degrees. | Tools/M10GDriver/Parser/Parser.Dx12.cs:873 |
| `S354` | SEMANTIC | DX12 camera field of view must be greater than 1 and less than 179 degrees. | Tools/M10GDriver/Parser/Parser.Dx12.cs:988 |
| `S356` | SEMANTIC | DX12 object rotation must be a vec3 of pitch/yaw/roll degrees. | Tools/M10GDriver/Parser/Parser.Dx12.cs:862 |
| `S360` | SEMANTIC | DX12 camera input delta must be a vec3.; Keyboard key cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1435; Tools/M10GDriver/Parser/Parser.Dx12.cs:1469 |
| `S371` | SEMANTIC | Native window styles only support the default state in M27D. | Tools/M10GDriver/Parser/Parser.Style.cs:389 |
| `S383` | SEMANTIC | DX12 mouse move camera sensitivity must be a vec2. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1262 |
| `S384` | SEMANTIC | DX12 mouse wheel camera delta must be a vec3. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1280 |
| `S385` | SEMANTIC | DX12 mouse button move delta must be a vec3. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1303 |
| `S388` | SEMANTIC | DX12 directional light name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1519 |
| `S390` | SEMANTIC | DX12 directional light direction must be a vec3.; DX12 directional light direction cannot be zero. | Tools/M10GDriver/Parser/Parser.Dx12.cs:891; Tools/M10GDriver/Parser/Parser.Dx12.cs:894 |
| `S391` | SEMANTIC | DX12 directional light intensity must be numeric.; DX12 directional light intensity must be between 0 and 4. | Tools/M10GDriver/Parser/Parser.Dx12.cs:910; Tools/M10GDriver/Parser/Parser.Dx12.cs:913 |
| `S392` | SEMANTIC | DX12 directional light ambient must be numeric.; DX12 directional light ambient must be between 0 and 1. | Tools/M10GDriver/Parser/Parser.Dx12.cs:929; Tools/M10GDriver/Parser/Parser.Dx12.cs:932 |
| `S393` | SEMANTIC | DX12 object selector name cannot be empty. | Tools/M10GDriver/Parser/Parser.Dx12.cs:1147 |
| `S396` | SEMANTIC | M29C selected object rotation requires a defined object selector.; M29C selected object rotation currently supports only axis y.; M29C selected object rotation currently supports only mouse x. (+2 more) | Tools/M10GDriver/Parser/Parser.Dx12.cs:1210; Tools/M10GDriver/Parser/Parser.Dx12.cs:1408; Tools/M10GDriver/Parser/Parser.Dx12.cs:1414 |
| `T001` | SEMANTIC | Unknown literal type for variable. | Tools/M10GDriver/Parser/Parser.Declarations.cs:48 |
