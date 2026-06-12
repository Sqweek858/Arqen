using System.Collections.Generic;
using System.Linq;

static partial class Program
{
    static IEnumerable<string> IrLines(AstModel ast, string sourcePath)
    {
        yield return "ARQIR|version=0";
        yield return $"TARGET|kind=program|name={Esc(ast.Program)}";
        yield return $"META|source={Esc(sourcePath.Replace('\\', '/'))}";
        foreach (var style in ast.Styles)
            yield return StyleIrLine(style);
        foreach (var style in ast.StylePresets)
            yield return StylePresetIrLine(style);
        foreach (var apply in ast.StyleApplications)
            yield return StyleApplyIrLine(apply);
        foreach (var obj in ast.UiObjects)
            yield return UiObjectIrLine(obj);
        foreach (var prop in ast.UiProperties)
            yield return UiPropertyIrLine(prop);
        foreach (var prop in ast.UiLayoutProperties)
            yield return UiLayoutIrLine(prop);
        foreach (var relation in ast.UiParents)
            yield return UiParentIrLine(relation);
        foreach (var dock in ast.UiDocks)
            yield return UiDockIrLine(dock);
        foreach (var ev in ast.UiEvents)
            yield return UiEventIrLine(ev);
        foreach (var binding in ast.UiBindings)
            yield return UiBindingIrLine(binding);
        foreach (var state in ast.UiStates)
            yield return UiStateIrLine(state);
        foreach (var resource in ast.UiResources)
            yield return UiResourceIrLine(resource);
        foreach (var use in ast.UiResourceUses)
            yield return UiResourceUseIrLine(use);
        foreach (var renderer in ast.Dx12Renderers)
            yield return Dx12RendererIrLine(renderer);
        foreach (var relation in ast.Dx12RendererParents)
            yield return Dx12ParentIrLine(relation);
        foreach (var clear in ast.Dx12RendererClearStyles)
            yield return Dx12ClearStyleIrLine(clear);
        foreach (var ready in ast.Dx12RendererClearReadies)
            yield return Dx12ClearReadyIrLine(ready);
        foreach (var frame in ast.Dx12FrameCommands)
            yield return Dx12FrameIrLine(frame);
        foreach (var shader in ast.Dx12Shaders)
            yield return Dx12ShaderIrLine(shader);
        foreach (var pipeline in ast.Dx12Pipelines)
            yield return Dx12PipelineIrLine(pipeline);
        foreach (var bind in ast.Dx12PipelineBinds)
            yield return Dx12PipelineBindIrLine(bind);
        foreach (var buffer in ast.Dx12VertexBuffers)
            yield return Dx12VertexBufferIrLine(buffer);
        foreach (var vertex in ast.Dx12Vertices)
            yield return Dx12VertexIrLine(vertex);
        foreach (var bind in ast.Dx12VertexBufferBinds)
            yield return Dx12VertexBufferBindIrLine(bind);
        foreach (var draw in ast.Dx12Draws)
            yield return Dx12DrawIrLine(draw);
        foreach (var obj in ast.Dx12Objects)
            yield return Dx12ObjectIrLine(obj);
        foreach (var binding in ast.Dx12ObjectBindings)
            yield return Dx12ObjectBindIrLine(binding);
        foreach (var drawObj in ast.Dx12DrawObjects)
            yield return Dx12DrawObjectIrLine(drawObj);
        foreach (var transform in ast.Dx12ObjectTransforms)
            yield return Dx12ObjectTransformIrLine(transform);
        foreach (var primitive in ast.Dx12ObjectPrimitives)
            yield return Dx12ObjectPrimitiveIrLine(primitive);
        foreach (var camera in ast.Dx12Cameras)
            yield return Dx12CameraIrLine(camera);
        foreach (var cameraUse in ast.Dx12CameraUses)
            yield return Dx12CameraUseIrLine(cameraUse);
        foreach (var projection in ast.Dx12CameraProjections)
            yield return Dx12CameraProjectionIrLine(projection);
        foreach (var cameraTransform in ast.Dx12CameraTransforms)
            yield return Dx12CameraTransformIrLine(cameraTransform);
        foreach (var key in ast.Dx12KeyBindings)
            yield return Dx12KeyBindingIrLine(key);
        foreach (var capture in ast.Dx12MouseCaptures)
            yield return Dx12MouseCaptureIrLine(capture);
        foreach (var move in ast.Dx12MouseMoveBindings)
            yield return Dx12MouseMoveIrLine(move);
        foreach (var button in ast.Dx12MouseButtonBindings)
            yield return Dx12MouseButtonIrLine(button);
        foreach (var wheel in ast.Dx12MouseWheelBindings)
            yield return Dx12MouseWheelIrLine(wheel);
        foreach (var selector in ast.Dx12ObjectSelectors)
            yield return Dx12ObjectSelectorIrLine(selector);
        foreach (var selectorUse in ast.Dx12ObjectSelectorUses)
            yield return Dx12ObjectSelectorUseIrLine(selectorUse);
        foreach (var select in ast.Dx12ObjectSelectionBindings)
            yield return Dx12ObjectSelectionBindingIrLine(select);
        foreach (var rotate in ast.Dx12SelectedObjectRotateBindings)
            yield return Dx12SelectedObjectRotateBindingIrLine(rotate);
        foreach (var light in ast.Dx12DirectionalLights)
            yield return Dx12DirectionalLightIrLine(light);
        foreach (var lightUse in ast.Dx12LightUses)
            yield return Dx12LightUseIrLine(lightUse);
        foreach (var prop in ast.Dx12LightProperties)
            yield return Dx12LightPropertyIrLine(prop);
        foreach (var buffer in ast.Dx12ConstantBuffers)
            yield return Dx12ConstantBufferIrLine(buffer);
        foreach (var bind in ast.Dx12ConstantBufferBinds)
            yield return Dx12ConstantBufferBindIrLine(bind);
        foreach (var sequence in ast.Dx12ColorSequences)
            yield return Dx12ColorSequenceIrLine(sequence);
        foreach (var key in ast.Dx12ColorKeys)
            yield return Dx12ColorKeyIrLine(key);
        foreach (var anim in ast.Dx12AnimateColors)
            yield return Dx12AnimateColorIrLine(anim);
        if (ast.RuntimeActions.Count > 0)
        {
            foreach (var v in ast.Vars)
                yield return IrSymbolLine(v.Name, v.Type, v.Value);
            for (var i = 0; i < ast.RuntimeActions.Count; i++)
                yield return RuntimeIrActionLine($"act_{i}", ast.RuntimeActions[i]);
            yield return IrActionLine($"act_{ast.RuntimeActions.Count}", "exit", "code=i32_0");
            yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
            yield return $"ENTRY|actions={string.Join(",", Enumerable.Range(0, ast.RuntimeActions.Count + 1).Select(i => $"act_{i}"))}";
            yield return "END";
            yield break;
        }
        yield return IrConstLine("str_0", "text", ast.Title);
        yield return IrConstLine("str_1", "text", ast.Message);
        yield return IrConstLine("i32_0", "int", ast.ExitCode.ToString());
        if (ast.MessageCommand == "print")
            yield return IrActionLine("act_0", "print_stdout", "text=str_1");
        else
            yield return IrActionLine("act_0", "show_message", "title=str_0|text=str_1");
        yield return IrActionLine("act_1", "exit", "code=i32_0");
        yield return "ENTRY|actions=act_0,act_1";
        yield return "END";
    }

    static string StyleIrLine(StyleProperty style)
        => $"STYLE|target={Esc(style.Target)}|state={Esc(style.State)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}";

    static string StylePresetIrLine(StylePresetProperty style)
        => $"STYLE_PRESET|name={Esc(style.Name)}|property={Esc(style.Property)}|kind={Esc(style.ValueKind)}|value={Esc(style.Value)}|unit={Esc(style.Unit)}";

    static string StyleApplyIrLine(StyleApplication apply)
        => $"STYLE_APPLY|style={Esc(apply.StyleName)}|target={Esc(apply.Target)}|state={Esc(apply.State)}";

    static string UiObjectIrLine(UiObject obj)
        => $"UI_OBJECT|type={Esc(obj.Type)}|name={Esc(obj.Name)}";

    static string UiPropertyIrLine(UiProperty prop)
        => $"UI_SET|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}";

    static string UiLayoutIrLine(UiLayoutProperty prop)
        => $"UI_LAYOUT|target={Esc(prop.Target)}|property={Esc(prop.Property)}|kind={Esc(prop.ValueKind)}|value={Esc(prop.Value)}|unit={Esc(prop.Unit)}";

    static string UiParentIrLine(UiParent relation)
        => $"UI_PARENT|child={Esc(relation.Child)}|parent={Esc(relation.Parent)}";

    static string UiDockIrLine(UiDock dock)
        => $"UI_DOCK|target={Esc(dock.Target)}|side={Esc(dock.Side)}|parent={Esc(dock.Parent)}";

    static string UiEventIrLine(UiEvent ev)
        => $"UI_EVENT|event={Esc(ev.Event)}|target={Esc(ev.Target)}|target_kind={Esc(ev.TargetKind)}|body_lines={ev.BodyLineCount}";

    static string UiBindingIrLine(UiBinding binding)
        => $"UI_BIND|target={Esc(binding.Target)}|property={Esc(binding.Property)}|source={Esc(binding.Source)}|source_type={Esc(binding.SourceType)}";

    static string UiStateIrLine(UiState state)
        => $"UI_STATE|target={Esc(state.Target)}|property={Esc(state.Property)}|kind={Esc(state.ValueKind)}|value={Esc(state.Value)}";

    static string UiResourceIrLine(UiResource resource)
        => $"UI_RESOURCE|type={Esc(resource.Type)}|name={Esc(resource.Name)}|path={Esc(resource.Path)}";

    static string UiResourceUseIrLine(UiResourceUse use)
        => $"UI_RESOURCE_USE|target={Esc(use.Target)}|property={Esc(use.Property)}|resource={Esc(use.ResourceName)}|resource_type={Esc(use.ResourceType)}";

    static string Dx12RendererIrLine(Dx12Renderer renderer)
        => $"DX12_RENDERER|name={Esc(renderer.Name)}";

    static string Dx12ParentIrLine(Dx12RendererParent relation)
        => $"DX12_PARENT|renderer={Esc(relation.Renderer)}|window={Esc(relation.Window)}";

    static string Dx12ClearStyleIrLine(Dx12RendererClearStyle clear)
        => $"DX12_CLEAR_STYLE|renderer={Esc(clear.Renderer)}|state={Esc(clear.State)}|kind={Esc(clear.ValueKind)}|value={Esc(clear.Value)}|unit={Esc(clear.Unit)}|source={Esc(clear.Source)}";

    static string Dx12ClearReadyIrLine(Dx12RendererClearReady ready)
        => $"DX12_CLEAR_READY|renderer={Esc(ready.Renderer)}|window={Esc(ready.Window)}|kind={Esc(ready.ValueKind)}|value={Esc(ready.Value)}|unit={Esc(ready.Unit)}|source={Esc(ready.Source)}";

    static string Dx12FrameIrLine(Dx12FrameCommand frame)
        => $"DX12_FRAME|command={Esc(frame.Command)}|renderer={Esc(frame.Renderer)}";

    static string Dx12ShaderIrLine(Dx12Shader shader)
        => $"DX12_SHADER|name={Esc(shader.Name)}|vertex={Esc(shader.VertexSource)}|pixel={Esc(shader.PixelSource)}";

    static string Dx12PipelineIrLine(Dx12Pipeline pipeline)
        => $"DX12_PIPELINE|name={Esc(pipeline.Name)}|renderer={Esc(pipeline.Renderer)}|shader={Esc(pipeline.Shader)}|topology={Esc(pipeline.Topology)}";

    static string Dx12PipelineBindIrLine(Dx12PipelineBind bind)
        => $"DX12_PIPELINE_BIND|pipeline={Esc(bind.Pipeline)}|renderer={Esc(bind.Renderer)}";

    static string Dx12VertexBufferIrLine(Dx12VertexBuffer buffer)
        => $"DX12_VERTEX_BUFFER|name={Esc(buffer.Name)}";

    static string Dx12VertexIrLine(Dx12Vertex vertex)
        => $"DX12_VERTEX|buffer={Esc(vertex.Buffer)}|index={vertex.Index}|position={Esc(vertex.Position)}|color={Esc(vertex.Color)}";

    static string Dx12VertexBufferBindIrLine(Dx12VertexBufferBind bind)
        => $"DX12_VERTEX_BUFFER_BIND|buffer={Esc(bind.Buffer)}|renderer={Esc(bind.Renderer)}";

    static string Dx12DrawIrLine(Dx12Draw draw)
        => $"DX12_DRAW|renderer={Esc(draw.Renderer)}|vertices={draw.Vertices}|buffer={Esc(draw.Buffer)}|pipeline={Esc(draw.Pipeline)}";

    static string Dx12ObjectIrLine(Dx12Object obj)
        => $"DX12_OBJECT|name={Esc(obj.Name)}";

    static string Dx12ObjectBindIrLine(Dx12ObjectBinding binding)
        => $"DX12_OBJECT_BIND|object={Esc(binding.Object)}|renderer={Esc(binding.Renderer)}|pipeline={Esc(binding.Pipeline)}|buffer={Esc(binding.VertexBuffer)}|vertices={binding.Vertices}";

    static string Dx12DrawObjectIrLine(Dx12DrawObject draw)
        => $"DX12_DRAW_OBJECT|object={Esc(draw.Object)}|renderer={Esc(draw.Renderer)}|vertices={draw.Vertices}|buffer={Esc(draw.Buffer)}|pipeline={Esc(draw.Pipeline)}";

    static string Dx12ObjectTransformIrLine(Dx12ObjectTransform transform)
        => $"DX12_OBJECT_TRANSFORM|object={Esc(transform.Object)}|property={Esc(transform.Property)}|value={Esc(transform.Value)}";

    static string Dx12ObjectPrimitiveIrLine(Dx12ObjectPrimitive primitive)
        => $"DX12_OBJECT_PRIMITIVE|object={Esc(primitive.Object)}|kind={Esc(primitive.Kind)}";

    static string Dx12CameraIrLine(Dx12Camera camera)
        => $"DX12_CAMERA|name={Esc(camera.Name)}";

    static string Dx12CameraUseIrLine(Dx12CameraUse cameraUse)
        => $"DX12_CAMERA_USE|camera={Esc(cameraUse.Camera)}|renderer={Esc(cameraUse.Renderer)}";

    static string Dx12CameraProjectionIrLine(Dx12CameraProjection projection)
        => $"DX12_CAMERA_PROJECTION|camera={Esc(projection.Camera)}|projection={Esc(projection.Projection)}";

    static string Dx12CameraTransformIrLine(Dx12CameraTransform cameraTransform)
        => $"DX12_CAMERA_TRANSFORM|camera={Esc(cameraTransform.Camera)}|property={Esc(cameraTransform.Property)}|value={Esc(cameraTransform.Value)}";

    static string Dx12KeyBindingIrLine(Dx12KeyBinding key)
        => $"DX12_KEY_BINDING|key={Esc(key.Key)}|action={Esc(key.Action)}|target={Esc(key.Target)}|delta={Esc(key.Delta)}";

    static string Dx12MouseCaptureIrLine(Dx12MouseCapture capture)
        => $"DX12_MOUSE_CAPTURE|window={Esc(capture.Window)}";

    static string Dx12MouseMoveIrLine(Dx12MouseMoveBinding move)
        => $"DX12_MOUSE_MOVE|target={Esc(move.Target)}|sensitivity={Esc(move.Sensitivity)}";

    static string Dx12MouseButtonIrLine(Dx12MouseButtonBinding button)
        => $"DX12_MOUSE_BUTTON|button={Esc(button.Button)}|action={Esc(button.Action)}|target={Esc(button.Target)}|delta={Esc(button.Delta)}";

    static string Dx12MouseWheelIrLine(Dx12MouseWheelBinding wheel)
        => $"DX12_MOUSE_WHEEL|action={Esc(wheel.Action)}|target={Esc(wheel.Target)}|delta={Esc(wheel.Delta)}";

    static string Dx12ObjectSelectorIrLine(Dx12ObjectSelector selector)
        => $"DX12_OBJECT_SELECTOR|name={Esc(selector.Name)}";

    static string Dx12ObjectSelectorUseIrLine(Dx12ObjectSelectorUse selectorUse)
        => $"DX12_OBJECT_SELECTOR_USE|selector={Esc(selectorUse.Selector)}|renderer={Esc(selectorUse.Renderer)}";

    static string Dx12ObjectSelectionBindingIrLine(Dx12ObjectSelectionBinding select)
        => $"DX12_OBJECT_SELECT_BINDING|button={Esc(select.Button)}|selector={Esc(select.Selector)}";

    static string Dx12SelectedObjectRotateBindingIrLine(Dx12SelectedObjectRotateBinding rotate)
        => $"DX12_SELECTED_OBJECT_ROTATE|key={Esc(rotate.Key)}|axis={Esc(rotate.Axis)}|mouse_axis={Esc(rotate.MouseAxis)}|sensitivity={Esc(rotate.Sensitivity)}";

    static string Dx12DirectionalLightIrLine(Dx12DirectionalLight light)
        => $"DX12_DIRECTIONAL_LIGHT|name={Esc(light.Name)}";

    static string Dx12LightUseIrLine(Dx12LightUse lightUse)
        => $"DX12_LIGHT_USE|light={Esc(lightUse.Light)}|renderer={Esc(lightUse.Renderer)}";

    static string Dx12LightPropertyIrLine(Dx12LightProperty prop)
        => $"DX12_LIGHT_PROPERTY|light={Esc(prop.Light)}|property={Esc(prop.Property)}|value={Esc(prop.Value)}";

    static string Dx12ConstantBufferIrLine(Dx12ConstantBuffer buffer)
        => $"DX12_CONSTANT_BUFFER|name={Esc(buffer.Name)}|field={Esc(buffer.Field)}|type={Esc(buffer.FieldType)}|value={Esc(buffer.Value)}";

    static string Dx12ConstantBufferBindIrLine(Dx12ConstantBufferBind bind)
        => $"DX12_CONSTANT_BUFFER_BIND|buffer={Esc(bind.Buffer)}|pipeline={Esc(bind.Pipeline)}";

    static string Dx12ColorSequenceIrLine(Dx12ColorSequence sequence)
        => $"DX12_COLOR_SEQUENCE|name={Esc(sequence.Name)}";

    static string Dx12ColorKeyIrLine(Dx12ColorKey key)
        => $"DX12_COLOR_KEY|sequence={Esc(key.Sequence)}|index={key.Index}|value={Esc(key.Value)}";

    static string Dx12AnimateColorIrLine(Dx12AnimateColor anim)
        => $"DX12_ANIMATE_COLOR|target={Esc(anim.Target)}|buffer={Esc(anim.Buffer)}|field={Esc(anim.Field)}|sequence={Esc(anim.Sequence)}|every_frames={anim.EveryFrames}";

    static string IrConstLine(string id, string type, string value) => $"CONST|id={id}|type={type}|value={Esc(value)}";
    static string IrSymbolLine(string name, string type, string value) => $"SYMBOL|name={Esc(name)}|type={Esc(type)}|value={Esc(value)}";
    static string IrActionLine(string id, string op, string fields) => $"ACTION|id={id}|op={op}|{fields}";
    static string RuntimeIrActionLine(string id, RuntimeAction action)
    {
        var fields = $"path={Esc(action.Path)}|value_kind={Esc(action.ValueKind)}|value={Esc(action.Value)}|target={Esc(action.Target)}";
        return IrActionLine(id, action.Op, fields);
    }
}
