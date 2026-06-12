using System.Collections.Generic;

static partial class Program
{
    static IEnumerable<string> AstLines(AstModel ast)
    {
        yield return $"PROGRAM|{Esc(ast.Program)}";
        foreach (var v in ast.Vars)
            yield return $"LET|{Esc(v.Name)}|{Esc(v.Type)}|{Esc(v.Value)}";
        foreach (var line in ast.Flow)
            yield return line;
        foreach (var line in AstStyleLines(ast))
            yield return line;
        foreach (var line in AstStylePresetLines(ast))
            yield return line;
        foreach (var line in AstStyleApplicationLines(ast))
            yield return line;
        foreach (var line in AstUiObjectLines(ast))
            yield return line;
        foreach (var line in AstUiPropertyLines(ast))
            yield return line;
        foreach (var line in AstUiLayoutLines(ast))
            yield return line;
        foreach (var line in AstUiParentLines(ast))
            yield return line;
        foreach (var line in AstUiDockLines(ast))
            yield return line;
        foreach (var line in AstUiFinalLines(ast))
            yield return line;
        foreach (var line in AstDx12Lines(ast))
            yield return line;
        foreach (var line in AstTitleLines(ast))
            yield return line;
        foreach (var line in AstMessageLines(ast))
            yield return line;
        foreach (var action in ast.RuntimeActions)
            yield return RuntimeAstLine(action);
        foreach (var line in AstFinalLines(ast))
            yield return line;
        yield return "SEMANTIC|OK";
    }


    static IEnumerable<string> AstStyleLines(AstModel ast)
    {
        foreach (var style in ast.Styles)
            yield return $"STYLE|target={Esc(style.Target)}|state={Esc(style.State)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}|source={Esc(style.Source)}";
    }

    static IEnumerable<string> AstStylePresetLines(AstModel ast)
    {
        foreach (var style in ast.StylePresets)
            yield return $"STYLE_PRESET|name={Esc(style.Name)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}|source={Esc(style.Source)}";
    }

    static IEnumerable<string> AstStyleApplicationLines(AstModel ast)
    {
        foreach (var apply in ast.StyleApplications)
            yield return $"STYLE_APPLY|style={Esc(apply.StyleName)}|target={Esc(apply.Target)}|state={Esc(apply.State)}";
    }

    static IEnumerable<string> AstUiObjectLines(AstModel ast)
    {
        foreach (var obj in ast.UiObjects)
            yield return $"UI_OBJECT|type={Esc(obj.Type)}|name={Esc(obj.Name)}";
    }

    static IEnumerable<string> AstUiPropertyLines(AstModel ast)
    {
        foreach (var prop in ast.UiProperties)
            yield return $"UI_SET|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|source={Esc(prop.Source)}";
    }

    static IEnumerable<string> AstUiLayoutLines(AstModel ast)
    {
        foreach (var prop in ast.UiLayoutProperties)
            yield return $"UI_LAYOUT|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|unit={Esc(prop.Unit)}|source={Esc(prop.Source)}";
    }

    static IEnumerable<string> AstUiParentLines(AstModel ast)
    {
        foreach (var relation in ast.UiParents)
            yield return $"UI_PARENT|child={Esc(relation.Child)}|parent={Esc(relation.Parent)}";
    }

    static IEnumerable<string> AstUiDockLines(AstModel ast)
    {
        foreach (var dock in ast.UiDocks)
            yield return $"UI_DOCK|target={Esc(dock.Target)}|side={Esc(dock.Side)}|parent={Esc(dock.Parent)}";
    }

    static IEnumerable<string> AstUiFinalLines(AstModel ast)
    {
        foreach (var ev in ast.UiEvents)
            yield return $"UI_EVENT|event={Esc(ev.Event)}|target={Esc(ev.Target)}|target_kind={Esc(ev.TargetKind)}|body_lines={ev.BodyLineCount}";
        foreach (var binding in ast.UiBindings)
            yield return $"UI_BIND|target={Esc(binding.Target)}|property={Esc(binding.Property)}|source={Esc(binding.Source)}|source_type={Esc(binding.SourceType)}";
        foreach (var state in ast.UiStates)
            yield return $"UI_STATE|target={Esc(state.Target)}|property={Esc(state.Property)}|kind={Esc(state.ValueKind)}|value={Esc(state.Value)}";
        foreach (var resource in ast.UiResources)
            yield return $"UI_RESOURCE|type={Esc(resource.Type)}|name={Esc(resource.Name)}|path={Esc(resource.Path)}";
        foreach (var use in ast.UiResourceUses)
            yield return $"UI_RESOURCE_USE|target={Esc(use.Target)}|property={Esc(use.Property)}|resource={Esc(use.ResourceName)}|resource_type={Esc(use.ResourceType)}";
    }

    static IEnumerable<string> AstDx12Lines(AstModel ast)
    {
        foreach (var renderer in ast.Dx12Renderers)
            yield return $"DX12_RENDERER|name={Esc(renderer.Name)}";
        foreach (var relation in ast.Dx12RendererParents)
            yield return $"DX12_PARENT|renderer={Esc(relation.Renderer)}|window={Esc(relation.Window)}";
        foreach (var clear in ast.Dx12RendererClearStyles)
            yield return $"DX12_CLEAR_STYLE|renderer={Esc(clear.Renderer)}|state={Esc(clear.State)}|kind={Esc(clear.ValueKind)}|value={Esc(clear.Value)}|unit={Esc(clear.Unit)}|source={Esc(clear.Source)}";
        foreach (var ready in ast.Dx12RendererClearReadies)
            yield return $"DX12_CLEAR_READY|renderer={Esc(ready.Renderer)}|window={Esc(ready.Window)}|kind={Esc(ready.ValueKind)}|value={Esc(ready.Value)}|unit={Esc(ready.Unit)}|source={Esc(ready.Source)}";
        foreach (var frame in ast.Dx12FrameCommands)
            yield return $"DX12_FRAME|command={Esc(frame.Command)}|renderer={Esc(frame.Renderer)}";
        foreach (var shader in ast.Dx12Shaders)
            yield return $"DX12_SHADER|name={Esc(shader.Name)}|vertex={Esc(shader.VertexSource)}|pixel={Esc(shader.PixelSource)}";
        foreach (var pipeline in ast.Dx12Pipelines)
            yield return $"DX12_PIPELINE|name={Esc(pipeline.Name)}|renderer={Esc(pipeline.Renderer)}|shader={Esc(pipeline.Shader)}|topology={Esc(pipeline.Topology)}";
        foreach (var bind in ast.Dx12PipelineBinds)
            yield return $"DX12_PIPELINE_BIND|pipeline={Esc(bind.Pipeline)}|renderer={Esc(bind.Renderer)}";
        foreach (var buffer in ast.Dx12VertexBuffers)
            yield return $"DX12_VERTEX_BUFFER|name={Esc(buffer.Name)}";
        foreach (var vertex in ast.Dx12Vertices)
            yield return $"DX12_VERTEX|buffer={Esc(vertex.Buffer)}|index={vertex.Index}|position={Esc(vertex.Position)}|color={Esc(vertex.Color)}";
        foreach (var bind in ast.Dx12VertexBufferBinds)
            yield return $"DX12_VERTEX_BUFFER_BIND|buffer={Esc(bind.Buffer)}|renderer={Esc(bind.Renderer)}";
        foreach (var draw in ast.Dx12Draws)
            yield return $"DX12_DRAW|renderer={Esc(draw.Renderer)}|vertices={draw.Vertices}|buffer={Esc(draw.Buffer)}|pipeline={Esc(draw.Pipeline)}";
        foreach (var obj in ast.Dx12Objects)
            yield return $"DX12_OBJECT|name={Esc(obj.Name)}";
        foreach (var binding in ast.Dx12ObjectBindings)
            yield return $"DX12_OBJECT_BIND|object={Esc(binding.Object)}|renderer={Esc(binding.Renderer)}|pipeline={Esc(binding.Pipeline)}|buffer={Esc(binding.VertexBuffer)}|vertices={binding.Vertices}";
        foreach (var drawObj in ast.Dx12DrawObjects)
            yield return $"DX12_DRAW_OBJECT|object={Esc(drawObj.Object)}|renderer={Esc(drawObj.Renderer)}|vertices={drawObj.Vertices}|buffer={Esc(drawObj.Buffer)}|pipeline={Esc(drawObj.Pipeline)}";
        foreach (var transform in ast.Dx12ObjectTransforms)
            yield return $"DX12_OBJECT_TRANSFORM|object={Esc(transform.Object)}|property={Esc(transform.Property)}|value={Esc(transform.Value)}";
        foreach (var primitive in ast.Dx12ObjectPrimitives)
            yield return $"DX12_OBJECT_PRIMITIVE|object={Esc(primitive.Object)}|kind={Esc(primitive.Kind)}";
        foreach (var camera in ast.Dx12Cameras)
            yield return $"DX12_CAMERA|name={Esc(camera.Name)}";
        foreach (var cameraUse in ast.Dx12CameraUses)
            yield return $"DX12_CAMERA_USE|camera={Esc(cameraUse.Camera)}|renderer={Esc(cameraUse.Renderer)}";
        foreach (var projection in ast.Dx12CameraProjections)
            yield return $"DX12_CAMERA_PROJECTION|camera={Esc(projection.Camera)}|projection={Esc(projection.Projection)}";
        foreach (var cameraTransform in ast.Dx12CameraTransforms)
            yield return $"DX12_CAMERA_TRANSFORM|camera={Esc(cameraTransform.Camera)}|property={Esc(cameraTransform.Property)}|value={Esc(cameraTransform.Value)}";
        foreach (var key in ast.Dx12KeyBindings)
            yield return $"DX12_KEY_BINDING|key={Esc(key.Key)}|action={Esc(key.Action)}|target={Esc(key.Target)}|delta={Esc(key.Delta)}";
        foreach (var capture in ast.Dx12MouseCaptures)
            yield return $"DX12_MOUSE_CAPTURE|window={Esc(capture.Window)}";
        foreach (var move in ast.Dx12MouseMoveBindings)
            yield return $"DX12_MOUSE_MOVE|target={Esc(move.Target)}|sensitivity={Esc(move.Sensitivity)}";
        foreach (var button in ast.Dx12MouseButtonBindings)
            yield return $"DX12_MOUSE_BUTTON|button={Esc(button.Button)}|action={Esc(button.Action)}|target={Esc(button.Target)}|delta={Esc(button.Delta)}";
        foreach (var wheel in ast.Dx12MouseWheelBindings)
            yield return $"DX12_MOUSE_WHEEL|action={Esc(wheel.Action)}|target={Esc(wheel.Target)}|delta={Esc(wheel.Delta)}";
        foreach (var buffer in ast.Dx12ConstantBuffers)
            yield return $"DX12_CONSTANT_BUFFER|name={Esc(buffer.Name)}|field={Esc(buffer.Field)}|type={Esc(buffer.FieldType)}|value={Esc(buffer.Value)}";
        foreach (var bind in ast.Dx12ConstantBufferBinds)
            yield return $"DX12_CONSTANT_BUFFER_BIND|buffer={Esc(bind.Buffer)}|pipeline={Esc(bind.Pipeline)}";
        foreach (var sequence in ast.Dx12ColorSequences)
            yield return $"DX12_COLOR_SEQUENCE|name={Esc(sequence.Name)}";
        foreach (var key in ast.Dx12ColorKeys)
            yield return $"DX12_COLOR_KEY|sequence={Esc(key.Sequence)}|index={key.Index}|value={Esc(key.Value)}";
        foreach (var anim in ast.Dx12AnimateColors)
            yield return $"DX12_ANIMATE_COLOR|target={Esc(anim.Target)}|buffer={Esc(anim.Buffer)}|field={Esc(anim.Field)}|sequence={Esc(anim.Sequence)}|every_frames={anim.EveryFrames}";
    }

    static IEnumerable<string> AstTitleLines(AstModel ast)
    {
        if (ast.TitleCommand == "set_title_to")
            yield return $"SET_TITLE|{Esc(ast.Title)}";
        yield return $"TITLE|{Esc(ast.Title)}";
        yield return $"TITLE_EXPR|{Esc(ast.TitleExpr)}";
    }

    static IEnumerable<string> AstMessageLines(AstModel ast)
    {
        if (ast.MessageCommand == "show_message")
            yield return $"SHOW_MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE|{Esc(ast.Message)}";
        yield return $"MESSAGE_EXPR|{Esc(ast.MessageExpr)}";
    }

    static string RuntimeAstLine(RuntimeAction action)
        => $"RUNTIME_ACTION|op={Esc(action.Op)}|path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";

    static IEnumerable<string> AstFinalLines(AstModel ast)
    {
        if (ast.FinalCommand == "blend_mix_to_code")
            yield return $"BLEND_MIX_TO_CODE|{ast.ExitCode}";
        else
            yield return $"EXIT|{ast.ExitCode}";
    }
}
