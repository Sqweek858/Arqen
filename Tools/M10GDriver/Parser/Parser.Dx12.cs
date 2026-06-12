using System;
using System.Collections.Generic;

static partial class Program
{
    sealed partial class Parser
    {
        // M20B DX12 syntax foundation: metadata only, no public backend support promotion.

        void ParseDx12RendererDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 renderer definitions inside compile-time if are not supported in M20B.");

            ExpectKeyword("define");
            ExpectWord("dx12", "P260", "Expected dx12 after define.");
            ExpectWord("renderer", "P260", "Expected renderer after dx12.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S260", nameTok.Line, nameTok.Column, "DX12 renderer name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S260", nameTok.Line, nameTok.Column, $"DX12 renderer '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12RendererNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S260", nameTok.Line, nameTok.Column, $"Duplicate DX12 renderer '{nameTok.Value}'.");

            if (apply)
                _dx12Renderers.Add(new Dx12Renderer(nameTok.Value));
        }

        void ParseDx12RendererParentStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 renderer parenting inside compile-time if is not supported in M20B.");

            ExpectWord("parent", "P261", "Expected parent statement.");
            ExpectWord("renderer", "P261", "Expected renderer after parent.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectKeyword("to");
            ExpectKeyword("window");
            var windowTok = Expect("STRING", "window name");
            ExpectLine();

            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S261", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            if (!_definedWindows.Contains(windowTok.Value))
                throw new CompileError("SEMANTIC", "S262", windowTok.Line, windowTok.Column, $"Window '{windowTok.Value}' is not defined.");
            if (_dx12RendererWindowByName.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S263", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' already has a parent window.");
            if (rendererTok.Value == windowTok.Value)
                throw new CompileError("SEMANTIC", "S264", rendererTok.Line, rendererTok.Column, "DX12 renderer cannot be parented to itself.");

            _dx12RendererWindowByName[rendererTok.Value] = windowTok.Value;
            if (apply)
                _dx12RendererParents.Add(new Dx12RendererParent(rendererTok.Value, windowTok.Value));
        }


        void ParseDx12FrameBeginStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 frame commands inside compile-time if are not supported in M20G.");

            ExpectWord("begin", "P268", "Expected begin statement.");
            ExpectWord("frame", "P268", "Expected frame after begin.");
            ExpectKeyword("of");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: false);
            if (_dx12FrameOpenRenderers.Contains(rendererTok.Value) || _dx12FrameEndedRenderers.Contains(rendererTok.Value) || _dx12FramePresentedRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' already has an active or completed frame in M20G.");

            _dx12FrameOpenRenderers.Add(rendererTok.Value);
            if (apply)
                _dx12FrameCommands.Add(new Dx12FrameCommand("begin", rendererTok.Value));
        }

        void ParseDx12RendererClearStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 clear commands inside compile-time if are not supported in M20G.");

            ExpectWord("clear", "P269", "Expected clear statement.");
            ExpectWord("renderer", "P269", "Expected renderer after clear.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: true);
            if (!_dx12FrameOpenRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' cannot be cleared outside an active frame.");
            if (!_dx12FrameClearedRenderers.Add(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' was already cleared in this M20G frame.");

            if (apply)
                _dx12FrameCommands.Add(new Dx12FrameCommand("clear", rendererTok.Value));
        }

        void ParseDx12FrameEndStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 frame commands inside compile-time if are not supported in M20G.");

            ExpectWord("end", "P270", "Expected end statement.");
            ExpectWord("frame", "P270", "Expected frame after end.");
            ExpectKeyword("of");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: false);
            if (!_dx12FrameOpenRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' has no active frame to end.");
            if (!_dx12FrameClearedRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' frame must clear before end frame in M20G.");

            _dx12FrameOpenRenderers.Remove(rendererTok.Value);
            _dx12FrameEndedRenderers.Add(rendererTok.Value);
            if (apply)
                _dx12FrameCommands.Add(new Dx12FrameCommand("end", rendererTok.Value));
        }

        void ParseDx12FramePresentStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 present commands inside compile-time if are not supported in M20G.");

            ExpectWord("present", "P271", "Expected present statement.");
            ExpectWord("frame", "P271", "Expected frame after present.");
            ExpectKeyword("of");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: false);
            if (!_dx12FrameEndedRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' frame must be ended before present frame.");
            if (!_dx12FramePresentedRenderers.Add(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S269", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' frame was already presented in M20G.");

            if (apply)
                _dx12FrameCommands.Add(new Dx12FrameCommand("present", rendererTok.Value));
        }

        void EnsureDx12FrameRendererReady(Token rendererTok, bool requireClearStyle)
        {
            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S268", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            if (!_dx12RendererWindowByName.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S268", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' must be parented to a window before frame commands.");
            if (requireClearStyle && !_dx12RendererClearStyleKeys.Contains(rendererTok.Value + "|default"))
                throw new CompileError("SEMANTIC", "S268", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' needs a default background color style before clear renderer.");
        }


        void ParseDx12ShaderDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 shader definitions inside compile-time if are not supported in M21B.");

            ExpectKeyword("define");
            ExpectWord("shader", "P280", "Expected shader after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 shader name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S280", nameTok.Line, nameTok.Column, "DX12 shader name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S280", nameTok.Line, nameTok.Column, $"DX12 shader '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12ShaderNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S280", nameTok.Line, nameTok.Column, $"Duplicate DX12 shader '{nameTok.Value}'.");

            string vertexSource = "";
            string pixelSource = "";
            SkipNewlines();
            while (!(CurrentWordIs("end") && PeekWord("shader")))
            {
                if (CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P280", nameTok.Line, nameTok.Column, "Expected end shader.");

                if (CurrentWordIs("vertex"))
                {
                    var propTok = Current;
                    Advance();
                    ExpectWord("source", "P280", "Expected source after vertex.");
                    ExpectKeyword("file");
                    var pathTok = Expect("STRING", "vertex shader source file");
                    ExpectLine();
                    if (string.IsNullOrWhiteSpace(pathTok.Value))
                        throw new CompileError("SEMANTIC", "S281", pathTok.Line, pathTok.Column, "Vertex shader source file cannot be empty.");
                    if (vertexSource != "")
                        throw new CompileError("SEMANTIC", "S281", propTok.Line, propTok.Column, $"DX12 shader '{nameTok.Value}' already has a vertex source file.");
                    vertexSource = pathTok.Value;
                }
                else if (CurrentWordIs("pixel"))
                {
                    var propTok = Current;
                    Advance();
                    ExpectWord("source", "P280", "Expected source after pixel.");
                    ExpectKeyword("file");
                    var pathTok = Expect("STRING", "pixel shader source file");
                    ExpectLine();
                    if (string.IsNullOrWhiteSpace(pathTok.Value))
                        throw new CompileError("SEMANTIC", "S281", pathTok.Line, pathTok.Column, "Pixel shader source file cannot be empty.");
                    if (pixelSource != "")
                        throw new CompileError("SEMANTIC", "S281", propTok.Line, propTok.Column, $"DX12 shader '{nameTok.Value}' already has a pixel source file.");
                    pixelSource = pathTok.Value;
                }
                else
                {
                    throw new CompileError("SEMANTIC", "S282", Current.Line, Current.Column, "Unsupported DX12 shader block property. Expected vertex source file or pixel source file.");
                }
                SkipNewlines();
            }

            ExpectWord("end", "P280", "Expected end shader.");
            ExpectWord("shader", "P280", "Expected shader after end.");
            ExpectLine();

            if (vertexSource == "")
                throw new CompileError("SEMANTIC", "S282", nameTok.Line, nameTok.Column, $"DX12 shader '{nameTok.Value}' requires a vertex source file.");
            if (pixelSource == "")
                throw new CompileError("SEMANTIC", "S282", nameTok.Line, nameTok.Column, $"DX12 shader '{nameTok.Value}' requires a pixel source file.");

            _dx12ShaderVertexByName[nameTok.Value] = vertexSource;
            _dx12ShaderPixelByName[nameTok.Value] = pixelSource;
            if (apply)
                _dx12Shaders.Add(new Dx12Shader(nameTok.Value, vertexSource, pixelSource));
        }

        void ParseDx12PipelineDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 pipeline definitions inside compile-time if are not supported in M21B.");

            ExpectKeyword("define");
            ExpectWord("dx12", "P283", "Expected dx12 after define.");
            ExpectWord("pipeline", "P283", "Expected pipeline after dx12.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 pipeline name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S283", nameTok.Line, nameTok.Column, "DX12 pipeline name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S283", nameTok.Line, nameTok.Column, $"DX12 pipeline '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12PipelineNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S283", nameTok.Line, nameTok.Column, $"Duplicate DX12 pipeline '{nameTok.Value}'.");

            string renderer = "";
            string shader = "";
            string topology = "";
            SkipNewlines();
            while (!(CurrentWordIs("end") && PeekWord("pipeline")))
            {
                if (CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P283", nameTok.Line, nameTok.Column, "Expected end pipeline.");

                if (CurrentWordIs("renderer"))
                {
                    var propTok = Current;
                    Advance();
                    Expect("COLON", "colon after renderer");
                    var rendererTok = Expect("STRING", "DX12 renderer name");
                    ExpectLine();
                    if (renderer != "")
                        throw new CompileError("SEMANTIC", "S284", propTok.Line, propTok.Column, $"DX12 pipeline '{nameTok.Value}' already has a renderer.");
                    if (!_dx12RendererNames.Contains(rendererTok.Value))
                        throw new CompileError("SEMANTIC", "S285", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
                    if (!_dx12RendererWindowByName.ContainsKey(rendererTok.Value))
                        throw new CompileError("SEMANTIC", "S285", rendererTok.Line, rendererTok.Column, $"DX12 pipeline renderer '{rendererTok.Value}' must be parented to a window.");
                    renderer = rendererTok.Value;
                }
                else if (CurrentWordIs("shader"))
                {
                    var propTok = Current;
                    Advance();
                    Expect("COLON", "colon after shader");
                    var shaderTok = Expect("STRING", "DX12 shader name");
                    ExpectLine();
                    if (shader != "")
                        throw new CompileError("SEMANTIC", "S284", propTok.Line, propTok.Column, $"DX12 pipeline '{nameTok.Value}' already has a shader.");
                    if (!_dx12ShaderNames.Contains(shaderTok.Value))
                        throw new CompileError("SEMANTIC", "S285", shaderTok.Line, shaderTok.Column, $"Unknown DX12 shader '{shaderTok.Value}'.");
                    shader = shaderTok.Value;
                }
                else if (CurrentWordIs("topology"))
                {
                    var propTok = Current;
                    Advance();
                    Expect("COLON", "colon after topology");
                    topology = ParseDx12Topology(propTok, nameTok.Value, topology);
                    ExpectLine();
                }
                else
                {
                    throw new CompileError("SEMANTIC", "S284", Current.Line, Current.Column, "Unsupported DX12 pipeline block property. Expected renderer, shader, or topology.");
                }
                SkipNewlines();
            }

            ExpectWord("end", "P283", "Expected end pipeline.");
            ExpectWord("pipeline", "P283", "Expected pipeline after end.");
            ExpectLine();

            if (renderer == "")
                throw new CompileError("SEMANTIC", "S284", nameTok.Line, nameTok.Column, $"DX12 pipeline '{nameTok.Value}' requires renderer.");
            if (shader == "")
                throw new CompileError("SEMANTIC", "S284", nameTok.Line, nameTok.Column, $"DX12 pipeline '{nameTok.Value}' requires shader.");
            if (topology == "")
                throw new CompileError("SEMANTIC", "S284", nameTok.Line, nameTok.Column, $"DX12 pipeline '{nameTok.Value}' requires topology.");

            _dx12PipelineRendererByName[nameTok.Value] = renderer;
            _dx12PipelineShaderByName[nameTok.Value] = shader;
            if (apply)
                _dx12Pipelines.Add(new Dx12Pipeline(nameTok.Value, renderer, shader, topology));
        }

        string ParseDx12Topology(Token propTok, string pipelineName, string currentTopology)
        {
            if (currentTopology != "")
                throw new CompileError("SEMANTIC", "S284", propTok.Line, propTok.Column, $"DX12 pipeline '{pipelineName}' already has topology.");

            if (CurrentWordIs("triangle") && PeekWord("list"))
            {
                Advance();
                Advance();
                return "triangle_list";
            }

            throw new CompileError("SEMANTIC", "S284", Current.Line, Current.Column, "Unsupported DX12 pipeline topology. Supported in M21B: triangle list.");
        }

        void ParseDx12PipelineUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 pipeline binding inside compile-time if is not supported in M21B/M23B.");

            ExpectKeyword("use");
            ExpectWord("pipeline", "P286", "Expected pipeline after use.");
            var pipelineTok = Expect("STRING", "DX12 pipeline name");
            ExpectKeyword("for");

            if (CurrentWordIs("object"))
            {
                ExpectWord("object", "P323", "Expected object after for.");
                var objectTok = Expect("STRING", "DX12 object name");
                ExpectLine();
                BindDx12ObjectPipeline(objectTok, pipelineTok);
                return;
            }

            ExpectWord("renderer", "P286", "Expected renderer after for.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            if (!_dx12PipelineNames.Contains(pipelineTok.Value))
                throw new CompileError("SEMANTIC", "S286", pipelineTok.Line, pipelineTok.Column, $"Unknown DX12 pipeline '{pipelineTok.Value}'.");
            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S286", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            if (!_dx12PipelineRendererByName.TryGetValue(pipelineTok.Value, out var pipelineRenderer) || pipelineRenderer != rendererTok.Value)
                throw new CompileError("SEMANTIC", "S286", rendererTok.Line, rendererTok.Column, $"DX12 pipeline '{pipelineTok.Value}' is not defined for renderer '{rendererTok.Value}'.");

            var key = pipelineTok.Value + "|" + rendererTok.Value;
            var rendererKey = "renderer|" + rendererTok.Value;
            if (_dx12PipelineBindKeys.Contains(key) || _dx12PipelineBindKeys.Contains(rendererKey))
                throw new CompileError("SEMANTIC", "S286", pipelineTok.Line, pipelineTok.Column, $"DX12 renderer '{rendererTok.Value}' already has a pipeline binding in M21B.");
            _dx12PipelineBindKeys.Add(key);
            _dx12PipelineBindKeys.Add(rendererKey);

            if (apply)
                _dx12PipelineBinds.Add(new Dx12PipelineBind(pipelineTok.Value, rendererTok.Value));
            _dx12PipelineByRenderer[rendererTok.Value] = pipelineTok.Value;
        }


        void ParseDx12VertexBufferDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 vertex buffer definitions inside compile-time if are not supported in M21C.");

            ExpectKeyword("define");
            ExpectWord("vertex", "P287", "Expected vertex after define.");
            ExpectWord("buffer", "P287", "Expected buffer after vertex.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 vertex buffer name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S287", nameTok.Line, nameTok.Column, "DX12 vertex buffer name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S287", nameTok.Line, nameTok.Column, $"DX12 vertex buffer '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12VertexBufferNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S287", nameTok.Line, nameTok.Column, $"Duplicate DX12 vertex buffer '{nameTok.Value}'.");

            var vertices = new List<(string Position, string Color)>();
            SkipNewlines();
            while (!(CurrentWordIs("end") && PeekWord("vertex") && PeekWord("buffer", 2)))
            {
                if (CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P287", nameTok.Line, nameTok.Column, "Expected end vertex buffer.");

                ExpectWord("vertex", "P288", "Expected vertex entry in vertex buffer block.");
                ExpectWord("position", "P288", "Expected position after vertex.");
                var posTok = Current;
                var position = ParseAddExpression(legacyQuotedStrings: false);
                if (position.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S288", posTok.Line, posTok.Column, "DX12 vertex position must be a vec3.");

                ExpectWord("color", "P288", "Expected color after vertex position.");
                var colorTok = Current;
                var color = ParseAddExpression(legacyQuotedStrings: false);
                if (color.Type != "vec4")
                    throw new CompileError("SEMANTIC", "S288", colorTok.Line, colorTok.Column, "DX12 vertex color must be a vec4.");
                var colorValues = ToVector(color);
                foreach (var component in colorValues)
                    if (component < 0 || component > 1)
                        throw new CompileError("SEMANTIC", "S288", colorTok.Line, colorTok.Column, "DX12 vertex color components must be between 0 and 1.");
                ExpectLine();

                vertices.Add((FormatVector(ToVector(position)), FormatVector(colorValues)));
                SkipNewlines();
            }

            ExpectWord("end", "P287", "Expected end vertex buffer.");
            ExpectWord("vertex", "P287", "Expected vertex after end.");
            ExpectWord("buffer", "P287", "Expected buffer after end vertex.");
            ExpectLine();

            if (vertices.Count < 3)
                throw new CompileError("SEMANTIC", "S289", nameTok.Line, nameTok.Column, $"DX12 vertex buffer '{nameTok.Value}' requires at least 3 vertices for M21C draw metadata.");

            _dx12VertexBufferCountByName[nameTok.Value] = vertices.Count;
            if (apply)
            {
                _dx12VertexBuffers.Add(new Dx12VertexBuffer(nameTok.Value));
                for (var i = 0; i < vertices.Count; i++)
                    _dx12Vertices.Add(new Dx12Vertex(nameTok.Value, i, vertices[i].Position, vertices[i].Color));
            }
        }

        void ParseDx12VertexBufferUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 vertex buffer binding inside compile-time if is not supported in M21C/M23B.");

            ExpectKeyword("use");
            ExpectWord("vertex", "P290", "Expected vertex after use.");
            ExpectWord("buffer", "P290", "Expected buffer after vertex.");
            var bufferTok = Expect("STRING", "DX12 vertex buffer name");
            ExpectKeyword("for");

            if (CurrentWordIs("object"))
            {
                ExpectWord("object", "P324", "Expected object after for.");
                var objectTok = Expect("STRING", "DX12 object name");
                ExpectLine();
                BindDx12ObjectVertexBuffer(objectTok, bufferTok);
                return;
            }

            ExpectWord("renderer", "P290", "Expected renderer after for.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            if (!_dx12VertexBufferNames.Contains(bufferTok.Value))
                throw new CompileError("SEMANTIC", "S290", bufferTok.Line, bufferTok.Column, $"Unknown DX12 vertex buffer '{bufferTok.Value}'.");
            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S291", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            if (!_dx12RendererWindowByName.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S291", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' must be parented to a window before binding a vertex buffer.");
            if (_dx12VertexBufferByRenderer.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S292", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' already has a vertex buffer binding in M21C.");

            _dx12VertexBufferByRenderer[rendererTok.Value] = bufferTok.Value;
            if (apply)
                _dx12VertexBufferBinds.Add(new Dx12VertexBufferBind(bufferTok.Value, rendererTok.Value));
        }

        void ParseDx12DrawStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 draw commands inside compile-time if are not supported in M21C/M23C.");

            ExpectWord("draw", "P293", "Expected draw statement.");

            if (CurrentIs("STRING"))
            {
                var objectTok = Expect("STRING", "DX12 object name");
                ExpectLine();
                ResolveAndAddDx12ObjectDraw(objectTok, apply);
                return;
            }

            var countTok = Expect("INT", "draw vertex count");
            ExpectWord("vertices", "P293", "Expected vertices after draw count.");

            if (!int.TryParse(countTok.Value, out var vertexCount) || vertexCount <= 0)
                throw new CompileError("SEMANTIC", "S293", countTok.Line, countTok.Column, "DX12 draw vertex count must be a positive integer.");

            if (CurrentWordIs("for"))
            {
                ExpectKeyword("for");
                ExpectWord("object", "P325", "Expected object after for.");
                var objectTok = Expect("STRING", "DX12 object name");
                ExpectLine();
                SetDx12ObjectVertexCount(objectTok, countTok, vertexCount);
                return;
            }

            if (CurrentWordIs("from"))
            {
                ExpectKeyword("from");
                ExpectWord("buffer", "P326", "Expected buffer after from.");
                var bufferTok = Expect("STRING", "DX12 vertex buffer name");
                ExpectKeyword("with");
                ExpectWord("pipeline", "P326", "Expected pipeline after with.");
                var pipelineTok = Expect("STRING", "DX12 pipeline name");
                ExpectWord("using", "P326", "Expected using after pipeline.");
                ExpectWord("renderer", "P326", "Expected renderer after using.");
                var rendererTok = Expect("STRING", "DX12 renderer name");
                ExpectLine();
                ValidateAndAddDx12Draw(rendererTok, countTok, vertexCount, bufferTok, pipelineTok, apply, allowMultipleForRenderer: true);
                return;
            }

            ExpectKeyword("with");
            ExpectWord("renderer", "P293", "Expected renderer after with.");
            var legacyRendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            if (!_dx12PipelineByRenderer.TryGetValue(legacyRendererTok.Value, out var pipeline))
                throw new CompileError("SEMANTIC", "S293", legacyRendererTok.Line, legacyRendererTok.Column, $"DX12 renderer '{legacyRendererTok.Value}' must have a pipeline binding before draw.");
            if (!_dx12VertexBufferByRenderer.TryGetValue(legacyRendererTok.Value, out var buffer))
                throw new CompileError("SEMANTIC", "S293", legacyRendererTok.Line, legacyRendererTok.Column, $"DX12 renderer '{legacyRendererTok.Value}' must have a vertex buffer binding before draw.");

            var bufferTok2 = new Token("STRING", buffer, countTok.Line, countTok.Column);
            var pipelineTok2 = new Token("STRING", pipeline, countTok.Line, countTok.Column);
            ValidateAndAddDx12Draw(legacyRendererTok, countTok, vertexCount, bufferTok2, pipelineTok2, apply, allowMultipleForRenderer: false);
        }




        void ParseDx12BoxPrimitiveDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 box primitive definitions inside compile-time if are not supported in M28A.");

            ExpectKeyword("define");
            ExpectWord("box", "P380", "Expected box after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 box object name");
            ExpectLine();

            ValidateNewDx12ObjectName(nameTok);
            if (!_dx12ObjectNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S380", nameTok.Line, nameTok.Column, $"Duplicate DX12 object '{nameTok.Value}'.");
            _dx12ObjectPrimitiveByName[nameTok.Value] = "box";
            if (apply)
            {
                _dx12Objects.Add(new Dx12Object(nameTok.Value));
                _dx12ObjectPrimitives.Add(new Dx12ObjectPrimitive(nameTok.Value, "box"));
            }
        }

        void ParseDx12ObjectDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 object definitions inside compile-time if are not supported in M23A.");

            ExpectKeyword("define");
            ExpectWord("object", "P320", "Expected object after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 object name");
            ExpectLine();

            ValidateNewDx12ObjectName(nameTok);
            if (!_dx12ObjectNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S320", nameTok.Line, nameTok.Column, $"Duplicate DX12 object '{nameTok.Value}'.");
            if (apply)
                _dx12Objects.Add(new Dx12Object(nameTok.Value));
        }

        void ValidateNewDx12ObjectName(Token nameTok)
        {
            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S320", nameTok.Line, nameTok.Column, "DX12 object name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S320", nameTok.Line, nameTok.Column, $"DX12 object '{nameTok.Value}' conflicts with an existing object name.");
        }

        void ParseDx12ObjectRendererUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 object renderer binding inside compile-time if is not supported in M23B.");

            ExpectKeyword("use");
            ExpectWord("renderer", "P322", "Expected renderer after use.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectKeyword("for");
            ExpectWord("object", "P322", "Expected object after for.");
            var objectTok = Expect("STRING", "DX12 object name");
            ExpectLine();

            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S322", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            ValidateExistingDx12Object(objectTok);
            if (_dx12ObjectRendererByName.ContainsKey(objectTok.Value))
                throw new CompileError("SEMANTIC", "S322", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has a renderer binding.");
            _dx12ObjectRendererByName[objectTok.Value] = rendererTok.Value;
        }

        void BindDx12ObjectPipeline(Token objectTok, Token pipelineTok)
        {
            ValidateExistingDx12Object(objectTok);
            if (!_dx12PipelineNames.Contains(pipelineTok.Value))
                throw new CompileError("SEMANTIC", "S323", pipelineTok.Line, pipelineTok.Column, $"Unknown DX12 pipeline '{pipelineTok.Value}'.");
            if (_dx12ObjectPipelineByName.ContainsKey(objectTok.Value))
                throw new CompileError("SEMANTIC", "S323", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has a pipeline binding.");
            _dx12ObjectPipelineByName[objectTok.Value] = pipelineTok.Value;
        }

        void BindDx12ObjectVertexBuffer(Token objectTok, Token bufferTok)
        {
            ValidateExistingDx12Object(objectTok);
            if (_dx12ObjectPrimitiveByName.ContainsKey(objectTok.Value))
                throw new CompileError("SEMANTIC", "S381", objectTok.Line, objectTok.Column, $"DX12 primitive object '{objectTok.Value}' owns generated vertex data and cannot bind a manual vertex buffer.");
            if (!_dx12VertexBufferNames.Contains(bufferTok.Value))
                throw new CompileError("SEMANTIC", "S324", bufferTok.Line, bufferTok.Column, $"Unknown DX12 vertex buffer '{bufferTok.Value}'.");
            if (_dx12ObjectVertexBufferByName.ContainsKey(objectTok.Value))
                throw new CompileError("SEMANTIC", "S324", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has a vertex buffer binding.");
            _dx12ObjectVertexBufferByName[objectTok.Value] = bufferTok.Value;
        }

        void SetDx12ObjectVertexCount(Token objectTok, Token countTok, int vertexCount)
        {
            ValidateExistingDx12Object(objectTok);
            if (vertexCount < 3)
                throw new CompileError("SEMANTIC", "S325", countTok.Line, countTok.Column, "DX12 object draw count must be at least 3 vertices.");
            if (_dx12ObjectVertexCountByName.ContainsKey(objectTok.Value))
                throw new CompileError("SEMANTIC", "S325", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has a draw vertex count.");
            _dx12ObjectVertexCountByName[objectTok.Value] = vertexCount;
        }

        void ValidateExistingDx12Object(Token objectTok)
        {
            if (!_dx12ObjectNames.Contains(objectTok.Value))
                throw new CompileError("SEMANTIC", "S321", objectTok.Line, objectTok.Column, $"Unknown DX12 object '{objectTok.Value}'.");
        }

        string ResolveDx12ObjectRenderer(Token objectTok)
        {
            if (_dx12ObjectRendererByName.TryGetValue(objectTok.Value, out var renderer))
                return renderer;

            var active = new List<string>();
            foreach (var rendererName in _dx12FrameOpenRenderers)
                if (_dx12FrameClearedRenderers.Contains(rendererName))
                    active.Add(rendererName);

            if (active.Count == 1)
                return active[0];

            if (_dx12RendererNames.Count == 1)
            {
                foreach (var rendererName in _dx12RendererNames)
                    return rendererName;
            }

            throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' needs an explicit renderer binding in this scene.");
        }

        (string Renderer, string Pipeline, string Buffer, int Vertices) ResolveDx12ObjectDrawFields(Token objectTok)
        {
            ValidateExistingDx12Object(objectTok);
            var renderer = ResolveDx12ObjectRenderer(objectTok);
            var rendererTok = new Token("STRING", renderer, objectTok.Line, objectTok.Column);
            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: false);
            if (!_dx12FrameOpenRenderers.Contains(renderer))
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' cannot draw because renderer '{renderer}' is outside an active frame.");
            if (!_dx12FrameClearedRenderers.Contains(renderer))
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' cannot draw before renderer '{renderer}' is cleared.");

            var pipeline = _dx12ObjectPipelineByName.TryGetValue(objectTok.Value, out var objectPipeline) ? objectPipeline : (_dx12PipelineByRenderer.TryGetValue(renderer, out var rendererPipeline) ? rendererPipeline : "");
            if (pipeline == "")
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' needs a pipeline binding or renderer '{renderer}' needs a default pipeline binding.");
            if (!_dx12PipelineNames.Contains(pipeline))
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' references unknown pipeline '{pipeline}'.");
            if (!_dx12PipelineRendererByName.TryGetValue(pipeline, out var pipelineRenderer) || pipelineRenderer != renderer)
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' pipeline '{pipeline}' is not defined for renderer '{renderer}'.");

            if (_dx12ObjectPrimitiveByName.TryGetValue(objectTok.Value, out var primitiveKind))
            {
                if (primitiveKind != "box")
                    throw new CompileError("SEMANTIC", "S381", objectTok.Line, objectTok.Column, $"Unsupported DX12 primitive kind '{primitiveKind}'.");
                if (_dx12ObjectVertexCountByName.ContainsKey(objectTok.Value))
                    throw new CompileError("SEMANTIC", "S381", objectTok.Line, objectTok.Column, $"DX12 box primitive '{objectTok.Value}' uses its generated 36-vertex draw count.");
                var primitiveBuffer = "__arqen_m28_box_" + objectTok.Value;
                return (renderer, pipeline, primitiveBuffer, 36);
            }

            var buffer = _dx12ObjectVertexBufferByName.TryGetValue(objectTok.Value, out var objectBuffer) ? objectBuffer : (_dx12VertexBufferByRenderer.TryGetValue(renderer, out var rendererBuffer) ? rendererBuffer : "");
            if (buffer == "")
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' needs a vertex buffer binding or renderer '{renderer}' needs a default vertex buffer binding.");
            if (!_dx12VertexBufferNames.Contains(buffer))
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' references unknown vertex buffer '{buffer}'.");
            if (!_dx12VertexBufferCountByName.TryGetValue(buffer, out var available))
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' vertex buffer '{buffer}' has no vertices.");

            var vertices = _dx12ObjectVertexCountByName.TryGetValue(objectTok.Value, out var objectVertices) ? objectVertices : available;
            if (vertices < 3 || vertices > available)
                throw new CompileError("SEMANTIC", "S326", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' draw count must be between 3 and vertex buffer count {available}.");
            return (renderer, pipeline, buffer, vertices);
        }

        void ResolveAndAddDx12ObjectDraw(Token objectTok, bool apply)
        {
            var resolved = ResolveDx12ObjectDrawFields(objectTok);
            var bindKey = objectTok.Value + "|" + resolved.Renderer + "|" + resolved.Pipeline + "|" + resolved.Buffer + "|" + resolved.Vertices;
            if (_dx12ObjectBindingKeys.Add(bindKey) && apply)
                _dx12ObjectBindings.Add(new Dx12ObjectBinding(objectTok.Value, resolved.Renderer, resolved.Pipeline, resolved.Buffer, resolved.Vertices));

            if (!_dx12DrawnObjects.Add(objectTok.Value))
                throw new CompileError("SEMANTIC", "S327", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has a draw command in this M23C frame.");

            if (apply)
            {
                _dx12DrawObjects.Add(new Dx12DrawObject(objectTok.Value, resolved.Renderer, resolved.Vertices, resolved.Buffer, resolved.Pipeline));
                _dx12Draws.Add(new Dx12Draw(resolved.Renderer, resolved.Vertices, resolved.Buffer, resolved.Pipeline));
            }
        }

        void ValidateAndAddDx12Draw(Token rendererTok, Token countTok, int vertexCount, Token bufferTok, Token pipelineTok, bool apply, bool allowMultipleForRenderer)
        {
            EnsureDx12FrameRendererReady(rendererTok, requireClearStyle: false);
            if (!_dx12FrameOpenRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S293", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' cannot draw outside an active frame.");
            if (!_dx12FrameClearedRenderers.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S293", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' must clear before draw in M21C/M23C.");
            if (!_dx12PipelineNames.Contains(pipelineTok.Value))
                throw new CompileError("SEMANTIC", "S293", pipelineTok.Line, pipelineTok.Column, $"Unknown DX12 pipeline '{pipelineTok.Value}'.");
            if (!_dx12PipelineRendererByName.TryGetValue(pipelineTok.Value, out var pipelineRenderer) || pipelineRenderer != rendererTok.Value)
                throw new CompileError("SEMANTIC", "S293", pipelineTok.Line, pipelineTok.Column, $"DX12 pipeline '{pipelineTok.Value}' is not defined for renderer '{rendererTok.Value}'.");
            if (!_dx12VertexBufferNames.Contains(bufferTok.Value))
                throw new CompileError("SEMANTIC", "S293", bufferTok.Line, bufferTok.Column, $"Unknown DX12 vertex buffer '{bufferTok.Value}'.");
            if (!_dx12VertexBufferCountByName.TryGetValue(bufferTok.Value, out var available) || vertexCount > available)
                throw new CompileError("SEMANTIC", "S293", countTok.Line, countTok.Column, $"DX12 draw requests {vertexCount} vertices but buffer '{bufferTok.Value}' has {available}.");
            if (vertexCount < 3)
                throw new CompileError("SEMANTIC", "S293", countTok.Line, countTok.Column, "DX12 draw requires at least 3 vertices.");
            if (!allowMultipleForRenderer && !_dx12DrawnRenderers.Add(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S293", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' already has a draw command in this M21C frame.");

            if (apply)
                _dx12Draws.Add(new Dx12Draw(rendererTok.Value, vertexCount, bufferTok.Value, pipelineTok.Value));
        }

        void FinalizeDx12ObjectBindings()
        {
            // M23A/B/C object bindings are finalized eagerly when draw "ObjectName" is parsed.
            // The hook exists so later M23+ passes can validate unused object definitions without
            // changing the parser lifecycle again.
        }

        bool LooksLikeDx12TransformOrCameraStatement()
            => (PeekWord("position") || PeekWord("rotation") || PeekWord("scale") || PeekWord("zoom") || PeekWord("camera") || PeekWord("field") || PeekWord("near") || PeekWord("far"));

        void ParseDx12TransformOrCameraStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 transform/camera statements inside compile-time if are not supported in M24/M25/M27.");

            ExpectKeyword("set");
            if (CurrentWordIs("camera"))
            {
                ExpectWord("camera", "P352", "Expected camera after set.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectWord("projection", "P352", "Expected projection after camera name.");
                ExpectKeyword("to");
                var projectionTok = Current;
                string projection;
                if (CurrentWordIs("orthographic"))
                {
                    projection = "orthographic";
                    Advance();
                }
                else if (CurrentWordIs("perspective"))
                {
                    projection = "perspective";
                    Advance();
                }
                else
                {
                    throw new CompileError("SEMANTIC", "S352", projectionTok.Line, projectionTok.Column, "DX12 camera projection must be orthographic or perspective.");
                }
                ExpectLine();
                AddDx12CameraProjection(cameraTok, projection, apply);
                return;
            }

            if (CurrentWordIs("position"))
            {
                ExpectWord("position", "P340", "Expected position after set.");
                ExpectKeyword("of");
                if (CurrentWordIs("object"))
                {
                    ExpectWord("object", "P340", "Expected object after of.");
                    var objectTok = Expect("STRING", "DX12 object name");
                    ExpectKeyword("to");
                    var valueTok = Current;
                    var position = ParseAddExpression(legacyQuotedStrings: false);
                    if (position.Type != "vec3")
                        throw new CompileError("SEMANTIC", "S340", valueTok.Line, valueTok.Column, "DX12 object position must be a vec3.");
                    ExpectLine();
                    AddDx12ObjectTransform(objectTok, "position", FormatVector(ToVector(position)), apply);
                    return;
                }
                if (CurrentWordIs("camera"))
                {
                    ExpectWord("camera", "P350", "Expected camera after of.");
                    var cameraTok = Expect("STRING", "DX12 camera name");
                    ExpectKeyword("to");
                    var valueTok = Current;
                    var position = ParseAddExpression(legacyQuotedStrings: false);
                    if (position.Type != "vec3")
                        throw new CompileError("SEMANTIC", "S350", valueTok.Line, valueTok.Column, "DX12 camera position must be a vec3.");
                    ExpectLine();
                    AddDx12CameraTransform(cameraTok, "position", FormatVector(ToVector(position)), apply);
                    return;
                }
                throw new CompileError("PARSE", "P340", Current.Line, Current.Column, "Expected object or camera after set position of.");
            }

            if (CurrentWordIs("rotation"))
            {
                ExpectWord("rotation", "P341", "Expected rotation after set.");
                if (CurrentWordIs("z"))
                {
                    ExpectWord("z", "P341", "Expected z after rotation.");
                    ExpectKeyword("of");
                    ExpectWord("object", "P341", "Expected object after of.");
                    var objectTok = Expect("STRING", "DX12 object name");
                    ExpectKeyword("to");
                    var valueTok = Current;
                    var rotationDegrees = ParseDx12SignedNumber(valueTok, "S341", "DX12 object rotation z must be numeric degrees.", consumeDeg: true);
                    ExpectLine();
                    AddDx12ObjectTransform(objectTok, "rotation_z", FormatNumber(rotationDegrees, "double"), apply);
                    return;
                }
                if (CurrentWordIs("of"))
                {
                    ExpectKeyword("of");
                    ExpectWord("camera", "P353", "Expected camera after of.");
                    var cameraTok = Expect("STRING", "DX12 camera name");
                    ExpectKeyword("to");
                    var valueTok = Current;
                    var rotation = ParseAddExpression(legacyQuotedStrings: false);
                    if (rotation.Type != "vec3")
                        throw new CompileError("SEMANTIC", "S353", valueTok.Line, valueTok.Column, "DX12 camera rotation must be a vec3 of pitch/yaw/roll degrees.");
                    ExpectLine();
                    AddDx12CameraTransform(cameraTok, "rotation", FormatVector(ToVector(rotation)), apply);
                    return;
                }
                throw new CompileError("PARSE", "P341", Current.Line, Current.Column, "Expected z for object rotation or of camera for camera rotation.");
            }

            if (CurrentWordIs("scale"))
            {
                ExpectWord("scale", "P342", "Expected scale after set.");
                ExpectKeyword("of");
                ExpectWord("object", "P342", "Expected object after of.");
                var objectTok = Expect("STRING", "DX12 object name");
                ExpectKeyword("to");
                var valueTok = Current;
                var scale = ParseAddExpression(legacyQuotedStrings: false);
                if (scale.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S342", valueTok.Line, valueTok.Column, "DX12 object scale must be a vec3.");
                var values = ToVector(scale);
                if (Math.Abs(values[0]) < NumericEpsilon || Math.Abs(values[1]) < NumericEpsilon || Math.Abs(values[2]) < NumericEpsilon)
                    throw new CompileError("SEMANTIC", "S342", valueTok.Line, valueTok.Column, "DX12 object scale components must be non-zero.");
                ExpectLine();
                AddDx12ObjectTransform(objectTok, "scale", FormatVector(values), apply);
                return;
            }

            if (CurrentWordIs("zoom"))
            {
                ExpectWord("zoom", "P351", "Expected zoom after set.");
                ExpectKeyword("of");
                ExpectWord("camera", "P351", "Expected camera after of.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("to");
                var valueTok = Current;
                var zoom = ParseAddExpression(legacyQuotedStrings: false);
                if (!IsNumeric(zoom.Type))
                    throw new CompileError("SEMANTIC", "S351", valueTok.Line, valueTok.Column, "DX12 camera zoom must be numeric.");
                var zoomValue = ToNumber(zoom);
                if (zoomValue <= NumericEpsilon)
                    throw new CompileError("SEMANTIC", "S351", valueTok.Line, valueTok.Column, "DX12 camera zoom must be positive.");
                ExpectLine();
                AddDx12CameraTransform(cameraTok, "zoom", FormatNumber(zoomValue, "double"), apply);
                return;
            }

            if (CurrentWordIs("field"))
            {
                ExpectWord("field", "P354", "Expected field after set.");
                ExpectKeyword("of");
                ExpectWord("view", "P354", "Expected view after field of.");
                ExpectKeyword("of");
                ExpectWord("camera", "P354", "Expected camera after field of view of.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("to");
                var valueTok = Current;
                var fov = ParseDx12SignedNumber(valueTok, "S354", "DX12 camera field of view must be numeric degrees.", consumeDeg: true);
                if (fov <= 1.0 || fov >= 179.0)
                    throw new CompileError("SEMANTIC", "S354", valueTok.Line, valueTok.Column, "DX12 camera field of view must be greater than 1 and less than 179 degrees.");
                ExpectLine();
                AddDx12CameraTransform(cameraTok, "fov_y_degrees", FormatNumber(fov, "double"), apply);
                return;
            }

            if (CurrentWordIs("near") || CurrentWordIs("far"))
            {
                var planeKind = Current.Value;
                if (CurrentWordIs("near"))
                    ExpectWord("near", "P355", "Expected near or far after set.");
                else
                    ExpectWord("far", "P356", "Expected near or far after set.");
                ExpectWord("plane", planeKind == "near" ? "P355" : "P356", "Expected plane after near/far.");
                ExpectKeyword("of");
                ExpectWord("camera", planeKind == "near" ? "P355" : "P356", "Expected camera after plane of.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("to");
                var valueTok = Current;
                var plane = ParseAddExpression(legacyQuotedStrings: false);
                if (!IsNumeric(plane.Type))
                    throw new CompileError("SEMANTIC", planeKind == "near" ? "S355" : "S356", valueTok.Line, valueTok.Column, $"DX12 camera {planeKind} plane must be numeric.");
                var planeValue = ToNumber(plane);
                if (planeValue <= NumericEpsilon)
                    throw new CompileError("SEMANTIC", planeKind == "near" ? "S355" : "S356", valueTok.Line, valueTok.Column, $"DX12 camera {planeKind} plane must be positive.");
                ExpectLine();
                AddDx12CameraTransform(cameraTok, planeKind == "near" ? "near_plane" : "far_plane", FormatNumber(planeValue, "double"), apply);
                return;
            }

            throw new CompileError("PARSE", "P340", Current.Line, Current.Column, "Expected DX12 transform/camera statement.");
        }

        double ParseDx12SignedNumber(Token valueTok, string semanticCode, string semanticMessage, bool consumeDeg)
        {
            var sign = 1.0;
            if (CurrentIs("MINUS") || CurrentIs("PLUS"))
            {
                sign = CurrentIs("MINUS") ? -1.0 : 1.0;
                Advance();
            }
            if (!CurrentIs("INT") && !CurrentIs("DECIMAL"))
                throw new CompileError("SEMANTIC", semanticCode, valueTok.Line, valueTok.Column, semanticMessage);
            var numberTok = Advance();
            if (!double.TryParse(numberTok.Value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var value))
                throw new CompileError("SEMANTIC", semanticCode, numberTok.Line, numberTok.Column, semanticMessage);
            if (consumeDeg && CurrentWordIs("deg"))
                ExpectWord("deg", "P354", "Expected deg.");
            return sign * value;
        }

        void AddDx12ObjectTransform(Token objectTok, string property, string value, bool apply)
        {
            ValidateExistingDx12Object(objectTok);
            var key = objectTok.Value + "|" + property;
            if (!_dx12ObjectTransformKeys.Add(key))
                throw new CompileError("SEMANTIC", "S340", objectTok.Line, objectTok.Column, $"DX12 object '{objectTok.Value}' already has transform property '{property}'.");
            if (apply)
                _dx12ObjectTransforms.Add(new Dx12ObjectTransform(objectTok.Value, property, value));
        }

        void ParseDx12CameraDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 camera definitions inside compile-time if are not supported in M25.");

            ExpectKeyword("define");
            ExpectWord("camera", "P348", "Expected camera after define.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 camera name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S348", nameTok.Line, nameTok.Column, "DX12 camera name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S348", nameTok.Line, nameTok.Column, $"DX12 camera '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12CameraNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S348", nameTok.Line, nameTok.Column, $"Duplicate DX12 camera '{nameTok.Value}'.");
            if (apply)
                _dx12Cameras.Add(new Dx12Camera(nameTok.Value));
        }

        void ParseDx12CameraUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 camera use statements inside compile-time if are not supported in M25.");

            ExpectKeyword("use");
            ExpectWord("camera", "P349", "Expected camera after use.");
            var cameraTok = Expect("STRING", "DX12 camera name");
            ExpectKeyword("for");
            ExpectWord("renderer", "P349", "Expected renderer after for.");
            var rendererTok = Expect("STRING", "DX12 renderer name");
            ExpectLine();

            ValidateExistingDx12Camera(cameraTok);
            if (!_dx12RendererNames.Contains(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S349", rendererTok.Line, rendererTok.Column, $"Unknown DX12 renderer '{rendererTok.Value}'.");
            if (!_dx12RendererWindowByName.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S349", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' must be parented to a window before using a camera.");
            if (_dx12CameraByRenderer.ContainsKey(rendererTok.Value))
                throw new CompileError("SEMANTIC", "S349", rendererTok.Line, rendererTok.Column, $"DX12 renderer '{rendererTok.Value}' already has a camera binding.");
            if (_dx12CameraRendererByName.ContainsKey(cameraTok.Value))
                throw new CompileError("SEMANTIC", "S349", cameraTok.Line, cameraTok.Column, $"DX12 camera '{cameraTok.Value}' is already bound to a renderer.");
            _dx12CameraByRenderer[rendererTok.Value] = cameraTok.Value;
            _dx12CameraRendererByName[cameraTok.Value] = rendererTok.Value;
            if (apply)
                _dx12CameraUses.Add(new Dx12CameraUse(cameraTok.Value, rendererTok.Value));
        }

        void AddDx12CameraProjection(Token cameraTok, string projection, bool apply)
        {
            ValidateExistingDx12Camera(cameraTok);
            if (projection != "orthographic" && projection != "perspective")
                throw new CompileError("SEMANTIC", "S352", cameraTok.Line, cameraTok.Column, "DX12 camera projection must be orthographic or perspective.");
            if (!_dx12CameraProjectionKeys.Add(cameraTok.Value))
                throw new CompileError("SEMANTIC", "S352", cameraTok.Line, cameraTok.Column, $"DX12 camera '{cameraTok.Value}' already has a projection.");
            if (apply)
                _dx12CameraProjections.Add(new Dx12CameraProjection(cameraTok.Value, projection));
        }

        void AddDx12CameraTransform(Token cameraTok, string property, string value, bool apply)
        {
            ValidateExistingDx12Camera(cameraTok);
            var key = cameraTok.Value + "|" + property;
            if (!_dx12CameraTransformKeys.Add(key))
                throw new CompileError("SEMANTIC", "S350", cameraTok.Line, cameraTok.Column, $"DX12 camera '{cameraTok.Value}' already has property '{property}'.");
            if (apply)
                _dx12CameraTransforms.Add(new Dx12CameraTransform(cameraTok.Value, property, value));
        }

        void ValidateExistingDx12Camera(Token cameraTok)
        {
            if (!_dx12CameraNames.Contains(cameraTok.Value))
                throw new CompileError("SEMANTIC", "S348", cameraTok.Line, cameraTok.Column, $"Unknown DX12 camera '{cameraTok.Value}'.");
        }



        // M28B syntax: capture mouse for window "MainWindow"
        void ParseDx12MouseCaptureStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 mouse capture statements inside compile-time if are not supported in M28B.");

            ExpectWord("capture", "P382", "Expected capture statement.");
            ExpectWord("mouse", "P382", "Expected mouse after capture.");
            ExpectKeyword("for");
            ExpectWord("window", "P382", "Expected window after for.");
            var windowTok = Expect("STRING", "window name");
            ExpectLine();

            if (!_definedWindows.Contains(windowTok.Value))
                throw new CompileError("SEMANTIC", "S382", windowTok.Line, windowTok.Column, $"Window '{windowTok.Value}' is not defined.");
            if (!_dx12MouseCaptureWindows.Add(windowTok.Value))
                throw new CompileError("SEMANTIC", "S382", windowTok.Line, windowTok.Column, $"Mouse capture for window '{windowTok.Value}' is already defined.");
            if (apply)
                _dx12MouseCaptures.Add(new Dx12MouseCapture(windowTok.Value));
        }

        // M28B syntax: when mouse moves rotate camera "MainCamera" by [0.12, 0.12]
        void ParseDx12MouseInputStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 mouse input statements inside compile-time if are not supported in M28B.");

            ExpectWord("when", "P383", "Expected when.");
            ExpectWord("mouse", "P383", "Expected mouse after when.");
            var kindTok = Current;

            if (CurrentWordIs("moves"))
            {
                ExpectWord("moves", "P383", "Expected moves after mouse.");
                ExpectWord("rotate", "P383", "Expected rotate after mouse moves.");
                ExpectWord("camera", "P383", "Expected camera after rotate.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("by");
                var sensitivityTok = Current;
                var sensitivity = ParseAddExpression(legacyQuotedStrings: false);
                if (sensitivity.Type != "vec2")
                    throw new CompileError("SEMANTIC", "S383", sensitivityTok.Line, sensitivityTok.Column, "DX12 mouse move camera sensitivity must be a vec2.");
                ExpectLine();
                ValidateExistingDx12Camera(cameraTok);
                AddDx12MouseMoveBinding(cameraTok, FormatVector(ToVector(sensitivity)), apply);
                return;
            }

            if (CurrentWordIs("wheel"))
            {
                ExpectWord("wheel", "P384", "Expected wheel after mouse.");
                ExpectWord("moves", "P384", "Expected moves after mouse wheel.");
                ExpectWord("move", "P384", "Expected move after mouse wheel moves.");
                ExpectWord("camera", "P384", "Expected camera after move.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("by");
                var deltaTok = Current;
                var delta = ParseAddExpression(legacyQuotedStrings: false);
                if (delta.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S384", deltaTok.Line, deltaTok.Column, "DX12 mouse wheel camera delta must be a vec3.");
                ExpectLine();
                ValidateExistingDx12Camera(cameraTok);
                AddDx12MouseWheelBinding("move_camera_wheel", cameraTok.Value, FormatVector(ToVector(delta)), cameraTok.Line, cameraTok.Column, apply);
                return;
            }

            if (CurrentWordIs("button"))
            {
                ExpectWord("button", "P385", "Expected button after mouse.");
                var buttonTok = Expect("STRING", "mouse button");
                ExpectKeyword("is");
                var stateTok = Current;
                if (CurrentWordIs("held"))
                {
                    ExpectWord("held", "P385", "Expected held or pressed after mouse button is.");
                    ExpectWord("move", "P385", "Expected move after held.");
                    ExpectWord("camera", "P385", "Expected camera after move.");
                    var cameraTok = Expect("STRING", "DX12 camera name");
                    ExpectKeyword("by");
                    var deltaTok = Current;
                    var delta = ParseAddExpression(legacyQuotedStrings: false);
                    if (delta.Type != "vec3")
                        throw new CompileError("SEMANTIC", "S385", deltaTok.Line, deltaTok.Column, "DX12 mouse button move delta must be a vec3.");
                    ExpectLine();
                    ValidateExistingDx12Camera(cameraTok);
                    AddDx12MouseButtonBinding(buttonTok, "move_camera_held", cameraTok.Value, FormatVector(ToVector(delta)), apply);
                    return;
                }
                if (CurrentWordIs("pressed"))
                {
                    ExpectWord("pressed", "P385", "Expected held or pressed after mouse button is.");
                    if (CurrentWordIs("reset"))
                    {
                        ExpectWord("reset", "P385", "Expected reset.");
                        ExpectWord("camera", "P385", "Expected camera after reset.");
                        var cameraTok = Expect("STRING", "DX12 camera name");
                        ExpectLine();
                        ValidateExistingDx12Camera(cameraTok);
                        AddDx12MouseButtonBinding(buttonTok, "reset_camera_pressed", cameraTok.Value, "[0,0,0]", apply);
                        return;
                    }
                    if (CurrentWordIs("toggle"))
                    {
                        ExpectWord("toggle", "P385", "Expected toggle.");
                        ExpectWord("animation", "P385", "Expected animation after toggle.");
                        ExpectLine();
                        AddDx12MouseButtonBinding(buttonTok, "toggle_animation_pressed", "", "[0,0,0]", apply);
                        return;
                    }
                }
                throw new CompileError("PARSE", "P385", stateTok.Line, stateTok.Column, "Expected DX12 mouse button action.");
            }

            throw new CompileError("PARSE", "P383", kindTok.Line, kindTok.Column, "Expected DX12 mouse input action.");
        }

        void AddDx12MouseMoveBinding(Token cameraTok, string sensitivity, bool apply)
        {
            var key = cameraTok.Value + "|rotate_camera_move";
            if (!_dx12MouseMoveBindingKeys.Add(key))
                throw new CompileError("SEMANTIC", "S383", cameraTok.Line, cameraTok.Column, $"Duplicate mouse move binding for camera '{cameraTok.Value}'.");
            if (apply)
                _dx12MouseMoveBindings.Add(new Dx12MouseMoveBinding(cameraTok.Value, sensitivity));
        }

        void AddDx12MouseWheelBinding(string action, string target, string delta, int line, int column, bool apply)
        {
            var key = action + "|" + target;
            if (!_dx12MouseWheelBindingKeys.Add(key))
                throw new CompileError("SEMANTIC", "S384", line, column, $"Duplicate mouse wheel binding for action '{action}' on '{target}'.");
            if (apply)
                _dx12MouseWheelBindings.Add(new Dx12MouseWheelBinding(action, target, delta));
        }

        void AddDx12MouseButtonBinding(Token buttonTok, string action, string target, string delta, bool apply)
        {
            var normalized = NormalizeDx12MouseButtonName(buttonTok.Value);
            if (normalized == "")
                throw new CompileError("SEMANTIC", "S385", buttonTok.Line, buttonTok.Column, $"Unsupported mouse button '{buttonTok.Value}'.");
            var key = normalized + "|" + action + "|" + target;
            if (!_dx12MouseButtonBindingKeys.Add(key))
                throw new CompileError("SEMANTIC", "S385", buttonTok.Line, buttonTok.Column, $"Duplicate mouse button binding '{buttonTok.Value}' for action '{action}'.");
            if (apply)
                _dx12MouseButtonBindings.Add(new Dx12MouseButtonBinding(normalized, action, target, delta));
        }

        string NormalizeDx12MouseButtonName(string button)
            => button switch
            {
                "Left" or "left" => "Left",
                "Right" or "right" => "Right",
                "Middle" or "middle" => "Middle",
                _ => ""
            };


        void ParseDx12KeyboardInputStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 keyboard input statements inside compile-time if are not supported in M26.");

            ExpectWord("when", "P360", "Expected when.");
            ExpectWord("key", "P360", "Expected key after when.");
            var keyTok = Expect("STRING", "keyboard key");
            ExpectKeyword("is");
            var stateTok = Current;
            if (CurrentWordIs("held"))
            {
                ExpectWord("held", "P360", "Expected held or pressed after key is.");
                ExpectWord("move", "P360", "Expected move after held.");
                ExpectWord("camera", "P360", "Expected camera after move.");
                var cameraTok = Expect("STRING", "DX12 camera name");
                ExpectKeyword("by");
                var deltaTok = Current;
                var delta = ParseAddExpression(legacyQuotedStrings: false);
                if (delta.Type != "vec3")
                    throw new CompileError("SEMANTIC", "S360", deltaTok.Line, deltaTok.Column, "DX12 camera input delta must be a vec3.");
                ExpectLine();
                ValidateExistingDx12Camera(cameraTok);
                AddDx12KeyBinding(keyTok, "move_camera_held", cameraTok.Value, FormatVector(ToVector(delta)), apply);
                return;
            }
            if (CurrentWordIs("pressed"))
            {
                ExpectWord("pressed", "P360", "Expected held or pressed after key is.");
                if (CurrentWordIs("reset"))
                {
                    ExpectWord("reset", "P360", "Expected reset.");
                    ExpectWord("camera", "P360", "Expected camera after reset.");
                    var cameraTok = Expect("STRING", "DX12 camera name");
                    ExpectLine();
                    ValidateExistingDx12Camera(cameraTok);
                    AddDx12KeyBinding(keyTok, "reset_camera_pressed", cameraTok.Value, "[0,0,0]", apply);
                    return;
                }
                if (CurrentWordIs("toggle"))
                {
                    ExpectWord("toggle", "P360", "Expected toggle.");
                    ExpectWord("animation", "P360", "Expected animation after toggle.");
                    ExpectLine();
                    AddDx12KeyBinding(keyTok, "toggle_animation_pressed", "", "[0,0,0]", apply);
                    return;
                }
            }
            throw new CompileError("PARSE", "P360", stateTok.Line, stateTok.Column, "Expected DX12 keyboard input action.");
        }

        void AddDx12KeyBinding(Token keyTok, string action, string target, string delta, bool apply)
        {
            if (string.IsNullOrWhiteSpace(keyTok.Value))
                throw new CompileError("SEMANTIC", "S360", keyTok.Line, keyTok.Column, "Keyboard key cannot be empty.");
            var normalized = NormalizeDx12KeyName(keyTok.Value);
            if (normalized == "")
                throw new CompileError("SEMANTIC", "S360", keyTok.Line, keyTok.Column, $"Unsupported keyboard key '{keyTok.Value}'.");
            var bindingKey = normalized + "|" + action + "|" + target;
            if (!_dx12KeyBindingKeys.Add(bindingKey))
                throw new CompileError("SEMANTIC", "S360", keyTok.Line, keyTok.Column, $"Duplicate keyboard binding '{keyTok.Value}' for action '{action}'.");
            if (apply)
                _dx12KeyBindings.Add(new Dx12KeyBinding(normalized, action, target, delta));
        }

        string NormalizeDx12KeyName(string key)
        {
            if (key.Length == 1 && char.IsLetterOrDigit(key[0]))
                return key.ToUpperInvariant();
            return key switch
            {
                "Space" or "space" => "Space",
                "Left" or "left" => "Left",
                "Right" or "right" => "Right",
                "Up" or "up" => "Up",
                "Down" or "down" => "Down",
                _ => ""
            };
        }



        void ParseDx12ConstantBufferDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 constant buffer definitions inside compile-time if are not supported in M21G.");

            ExpectKeyword("define");
            ExpectWord("constant", "P294", "Expected constant after define.");
            ExpectWord("buffer", "P294", "Expected buffer after constant.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 constant buffer name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S294", nameTok.Line, nameTok.Column, "DX12 constant buffer name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ColorSequenceNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value) || _dx12CameraNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S294", nameTok.Line, nameTok.Column, $"DX12 constant buffer '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12ConstantBufferNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S294", nameTok.Line, nameTok.Column, $"Duplicate DX12 constant buffer '{nameTok.Value}'.");

            string tint = "";
            SkipNewlines();
            while (!(CurrentWordIs("end") && PeekWord("constant") && PeekWord("buffer", 2)))
            {
                if (CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P294", nameTok.Line, nameTok.Column, "Expected end constant buffer.");

                if (CurrentWordIs("color"))
                {
                    var propTok = Current;
                    Advance();
                    var fieldTok = Current;
                    if (!CurrentWordIs("tint"))
                        throw new CompileError("SEMANTIC", "S295", fieldTok.Line, fieldTok.Column, "M21G supports only color tint in DX12 constant buffers.");
                    Advance();
                    Expect("COLON", "colon after constant buffer field");
                    var valueTok = Current;
                    var value = ParseAddExpression(legacyQuotedStrings: false);
                    ExpectLine();
                    if (value.Type != "color")
                        throw new CompileError("SEMANTIC", "S295", valueTok.Line, valueTok.Column, "DX12 constant buffer tint requires a color value.");
                    if (tint != "")
                        throw new CompileError("SEMANTIC", "S296", propTok.Line, propTok.Column, $"DX12 constant buffer '{nameTok.Value}' already has tint.");
                    tint = value.Value;
                }
                else
                {
                    throw new CompileError("SEMANTIC", "S295", Current.Line, Current.Column, "Unsupported DX12 constant buffer field. Supported in M21G: color tint.");
                }
                SkipNewlines();
            }

            ExpectWord("end", "P294", "Expected end constant buffer.");
            ExpectWord("constant", "P294", "Expected constant after end.");
            ExpectWord("buffer", "P294", "Expected buffer after end constant.");
            ExpectLine();

            if (tint == "")
                throw new CompileError("SEMANTIC", "S295", nameTok.Line, nameTok.Column, $"DX12 constant buffer '{nameTok.Value}' requires color tint.");

            _dx12ConstantBufferTintByName[nameTok.Value] = tint;
            if (apply)
                _dx12ConstantBuffers.Add(new Dx12ConstantBuffer(nameTok.Value, "tint", "color4", tint));
        }

        void ParseDx12ConstantBufferUseStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 constant buffer binding inside compile-time if is not supported in M21G.");

            ExpectKeyword("use");
            ExpectWord("constant", "P297", "Expected constant after use.");
            ExpectWord("buffer", "P297", "Expected buffer after constant.");
            var bufferTok = Expect("STRING", "DX12 constant buffer name");
            ExpectKeyword("for");
            ExpectWord("pipeline", "P297", "Expected pipeline after for.");
            var pipelineTok = Expect("STRING", "DX12 pipeline name");
            ExpectLine();

            if (!_dx12ConstantBufferNames.Contains(bufferTok.Value))
                throw new CompileError("SEMANTIC", "S297", bufferTok.Line, bufferTok.Column, $"Unknown DX12 constant buffer '{bufferTok.Value}'.");
            if (!_dx12PipelineNames.Contains(pipelineTok.Value))
                throw new CompileError("SEMANTIC", "S298", pipelineTok.Line, pipelineTok.Column, $"Unknown DX12 pipeline '{pipelineTok.Value}'.");
            if (_dx12ConstantBufferByPipeline.ContainsKey(pipelineTok.Value))
                throw new CompileError("SEMANTIC", "S299", pipelineTok.Line, pipelineTok.Column, $"DX12 pipeline '{pipelineTok.Value}' already has a constant buffer binding in M21G.");

            var key = bufferTok.Value + "|" + pipelineTok.Value;
            if (!_dx12ConstantBufferBindKeys.Add(key))
                throw new CompileError("SEMANTIC", "S299", bufferTok.Line, bufferTok.Column, $"Duplicate DX12 constant buffer binding '{bufferTok.Value}' for pipeline '{pipelineTok.Value}'.");

            _dx12ConstantBufferByPipeline[pipelineTok.Value] = bufferTok.Value;
            if (apply)
                _dx12ConstantBufferBinds.Add(new Dx12ConstantBufferBind(bufferTok.Value, pipelineTok.Value));
        }

        void ParseDx12ColorSequenceDefinitionStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 color sequence definitions inside compile-time if are not supported in M21H.");

            ExpectKeyword("define");
            ExpectWord("color", "P300", "Expected color after define.");
            ExpectWord("sequence", "P300", "Expected sequence after color.");
            ExpectKeyword("called");
            var nameTok = Expect("STRING", "DX12 color sequence name");
            ExpectLine();

            if (string.IsNullOrWhiteSpace(nameTok.Value))
                throw new CompileError("SEMANTIC", "S300", nameTok.Line, nameTok.Column, "DX12 color sequence name cannot be empty.");
            if (SymbolExists(nameTok.Value) || _definedWindows.Contains(nameTok.Value) || _uiObjectTypes.ContainsKey(nameTok.Value) || _dx12RendererNames.Contains(nameTok.Value) || _dx12ShaderNames.Contains(nameTok.Value) || _dx12PipelineNames.Contains(nameTok.Value) || _dx12VertexBufferNames.Contains(nameTok.Value) || _dx12ConstantBufferNames.Contains(nameTok.Value) || _dx12ObjectNames.Contains(nameTok.Value))
                throw new CompileError("SEMANTIC", "S300", nameTok.Line, nameTok.Column, $"DX12 color sequence '{nameTok.Value}' conflicts with an existing object name.");
            if (!_dx12ColorSequenceNames.Add(nameTok.Value))
                throw new CompileError("SEMANTIC", "S300", nameTok.Line, nameTok.Column, $"Duplicate DX12 color sequence '{nameTok.Value}'.");

            var colors = new List<string>();
            SkipNewlines();
            while (!(CurrentWordIs("end") && PeekWord("color") && PeekWord("sequence", 2)))
            {
                if (CurrentIs("EOF"))
                    throw new CompileError("PARSE", "P300", nameTok.Line, nameTok.Column, "Expected end color sequence.");
                ExpectWord("color", "P301", "Expected color entry in color sequence.");
                var colorTok = Current;
                if (CurrentIs("LBRACKET"))
                    throw new CompileError("SEMANTIC", "S301", colorTok.Line, colorTok.Column, "DX12 color sequence entries must be color literals, not vectors.");
                var value = ParseColorLiteralExpression();
                ExpectLine();
                if (value.Type != "color")
                    throw new CompileError("SEMANTIC", "S301", colorTok.Line, colorTok.Column, "DX12 color sequence entries must be color literals.");
                colors.Add(value.Value);
                SkipNewlines();
            }

            ExpectWord("end", "P300", "Expected end color sequence.");
            ExpectWord("color", "P300", "Expected color after end.");
            ExpectWord("sequence", "P300", "Expected sequence after end color.");
            ExpectLine();

            if (colors.Count < 2)
                throw new CompileError("SEMANTIC", "S302", nameTok.Line, nameTok.Column, $"DX12 color sequence '{nameTok.Value}' requires at least two colors.");

            _dx12ColorSequenceCountByName[nameTok.Value] = colors.Count;
            if (apply)
            {
                _dx12ColorSequences.Add(new Dx12ColorSequence(nameTok.Value));
                for (var i = 0; i < colors.Count; i++)
                    _dx12ColorKeys.Add(new Dx12ColorKey(nameTok.Value, i, colors[i]));
            }
        }

        void ParseDx12AnimateColorStatement(bool apply, bool inIf)
        {
            if (inIf)
                throw new CompileError("SEMANTIC", "S024", Current.Line, Current.Column, "DX12 color animation inside compile-time if is not supported in M21H.");

            ExpectWord("animate", "P303", "Expected animate statement.");
            ExpectWord("color", "P303", "Expected color after animate.");
            var targetTok = Expect("STRING", "constant buffer color target");
            ExpectLine();
            ExpectWord("using", "P303", "Expected using sequence in animate color block.");
            ExpectWord("sequence", "P303", "Expected sequence after using.");
            var sequenceTok = Expect("STRING", "DX12 color sequence name");
            ExpectLine();
            ExpectWord("every", "P303", "Expected every in animate color block.");
            var everyTok = Expect("INT", "animation frame interval");
            ExpectWord("frames", "P303", "Expected frames after animation interval.");
            ExpectLine();
            ExpectWord("end", "P303", "Expected end animate.");
            ExpectWord("animate", "P303", "Expected animate after end.");
            ExpectLine();

            var dot = targetTok.Value.IndexOf('.', StringComparison.Ordinal);
            if (dot <= 0 || dot == targetTok.Value.Length - 1)
                throw new CompileError("SEMANTIC", "S303", targetTok.Line, targetTok.Column, "DX12 animate color target must be ConstantBuffer.field, for example TriangleParams.tint.");
            var buffer = targetTok.Value[..dot];
            var field = targetTok.Value[(dot + 1)..];
            if (!_dx12ConstantBufferNames.Contains(buffer) || field != "tint")
                throw new CompileError("SEMANTIC", "S303", targetTok.Line, targetTok.Column, $"Unknown DX12 constant buffer color target '{targetTok.Value}'.");
            if (!_dx12ColorSequenceNames.Contains(sequenceTok.Value))
                throw new CompileError("SEMANTIC", "S304", sequenceTok.Line, sequenceTok.Column, $"Unknown DX12 color sequence '{sequenceTok.Value}'.");
            if (!int.TryParse(everyTok.Value, out var everyFrames) || everyFrames <= 0)
                throw new CompileError("SEMANTIC", "S305", everyTok.Line, everyTok.Column, "DX12 color animation interval must be a positive integer.");

            var boundPipelineCount = 0;
            foreach (var bind in _dx12ConstantBufferByPipeline)
                if (bind.Value == buffer)
                    boundPipelineCount++;
            if (boundPipelineCount == 0)
                throw new CompileError("SEMANTIC", "S307", targetTok.Line, targetTok.Column, $"DX12 color animation target '{targetTok.Value}' must be bound to a pipeline before animate color in M21J.");
            if (boundPipelineCount > 1)
                throw new CompileError("SEMANTIC", "S307", targetTok.Line, targetTok.Column, $"DX12 color animation target '{targetTok.Value}' must be bound to exactly one pipeline in M21J.");

            if (!_dx12AnimateColorTargets.Add(targetTok.Value))
                throw new CompileError("SEMANTIC", "S306", targetTok.Line, targetTok.Column, $"DX12 color target '{targetTok.Value}' already has an animation in M21H.");

            if (apply)
                _dx12AnimateColors.Add(new Dx12AnimateColor(targetTok.Value, buffer, field, sequenceTok.Value, everyFrames));
        }

        void FinalizeDx12RendererClearReadiness()
        {
            var readyRenderers = new HashSet<string>(StringComparer.Ordinal);
            foreach (var clear in _dx12RendererClearStyles)
            {
                if (!_dx12RendererWindowByName.TryGetValue(clear.Renderer, out var window))
                    continue;
                if (!readyRenderers.Add(clear.Renderer))
                    continue;
                _dx12RendererClearReadies.Add(new Dx12RendererClearReady(clear.Renderer, window, clear.ValueKind, clear.Value, clear.Unit, clear.Source));
            }
        }
    }
}
