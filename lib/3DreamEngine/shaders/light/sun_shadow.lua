local sh = { }

sh.type = "light"

sh.func = "sampleShadowSun"

function sh:constructDefinesGlobal(dream)
	return [[
	// NationsRTS: PCF bilineal de 2 x 2 con el texel real del mapa de sombra.
	// El original desplazaba 1/ancho de la pantalla y tramaba por bloques de
	// 2 x 2 píxeles: el borde de la sombra salía en damero.
	float sampleShadowSun2(Image tex, vec2 shadowUV, float depth) {
		vec2 size = vec2(textureSize(tex, 0));
		vec2 st = shadowUV * size - 0.5;
		vec2 i = floor(st);
		vec2 f = st - i;
		vec2 uv = (i + 0.5) / size;
		vec2 px = 1.0 / size;
		
		float r0 = texture(tex, uv).x > depth ? 1.0 : 0.0;
		float r1 = texture(tex, uv + vec2(px.x, 0.0)).x > depth ? 1.0 : 0.0;
		float r2 = texture(tex, uv + vec2(0.0, px.y)).x > depth ? 1.0 : 0.0;
		float r3 = texture(tex, uv + px).x > depth ? 1.0 : 0.0;
		
		return mix(mix(r0, r1, f.x), mix(r2, r3, f.x), f.y);
	}
	]] .. self:constructDefinesGlobalCommon(dream)
end

function sh:constructDefinesGlobalCommon(dream)
	return [[
	float ]] .. self.func .. [[(vec3 vertexPos, vec3 pos, mat4 proj1, mat4 proj2, mat4 proj3, Image tex1, Image tex2, Image tex3, float factor, float shadowDistance, float fade, float bias) {
		float dist = distance(vertexPos, pos) * shadowDistance;
		
		float f2 = factor * factor;
		float v1 = clamp((1.0 - dist) * fade * f2, 0.0, 1.0);
		float v2 = clamp((factor - dist) * fade * factor, 0.0, 1.0) - v1;
		float v3 = clamp((f2 - dist) * fade, 0.0, 1.0) - v2 - v1;
		
		float v = 1.0 - v1 - v2 - v3;
		if (v1 > 0.0) {
			vec3 uvs = (proj1 * vec4(vertexPos, 1.0)).xyz;
			v += v1 * ]] .. self.func ..[[2(tex1, uvs.xy * 0.5 + 0.5, uvs.z - bias);
		}
		if (v2 > 0.0) {
			vec3 uvs = (proj2 * vec4(vertexPos, 1.0)).xyz;
			v += v2 * ]] .. self.func ..[[2(tex2, uvs.xy * 0.5 + 0.5, uvs.z - bias * factor);
		}
		if (v3 > 0.0) {
			vec3 uvs = (proj3 * vec4(vertexPos, 1.0)).xyz;
			v += v3 * ]] .. self.func ..[[2(tex3, uvs.xy * 0.5 + 0.5, uvs.z - bias * f2);
		}
		return v;
	}
	]]
end

function sh:constructDefines(ID)
	return ([[
	uniform float ss_factor_#ID#;
	uniform float ss_distance_#ID#;
	uniform float ss_fade_#ID#;
	
	uniform vec3 ss_pos_#ID#;
	
	uniform mat4 ss_proj1_#ID#;
	uniform mat4 ss_proj2_#ID#;
	uniform mat4 ss_proj3_#ID#;
	
	uniform Image ss_tex1_#ID#;
	uniform Image ss_tex2_#ID#;
	uniform Image ss_tex3_#ID#;
	
	uniform vec3 ss_vec_#ID#;
	uniform vec3 ss_color_#ID#;
	]]):gsub("#ID#", ID)
end

function sh:constructPixelGlobal(dream)

end

function sh:constructPixel(ID)
	return ([[
	// NationsRTS: con la normal del vértice (la del mapa de normales hacía acné)
	// y escalado por setShadowBias.
	float bias = mix(1.0, 0.01, dot(normalize(varyingNormal), ss_vec_#ID#)) / 512.0 * #BIAS#;
	float shadow = ]] .. self.func .. [[(vertexPos, ss_pos_#ID#, ss_proj1_#ID#, ss_proj2_#ID#, ss_proj3_#ID#, ss_tex1_#ID#, ss_tex2_#ID#, ss_tex3_#ID#, ss_factor_#ID#, ss_distance_#ID#, ss_fade_#ID#, bias);
	
	if (shadow > 0.0) {
		vec3 lightColor = ss_color_#ID# * shadow;
		
		light += getLight(lightColor, viewVec, ss_vec_#ID#, normal, albedo, roughness, metallic);
	}
	]]):gsub("#ID#", ID):gsub("#BIAS#", string.format("%.6f", _3DreamEngine.shadowBias or 1.0))
end

function sh:sendGlobalUniforms(shaderObject)
	
end

function sh:sendUniforms(shaderObject, light, ID)
	local shader = shaderObject.shader
	
	if light.shadow.canvases and light.shadow.canvases[3] then
		shader:send("ss_factor_" .. ID, light.shadow.cascadeFactor)
		shader:send("ss_fade_" .. ID, 4 / light.shadow.cascadeFactor / light.shadow.cascadeFactor)
		shader:send("ss_distance_" .. ID, 2 / light.shadow.cascadeDistance)
		
		shader:send("ss_pos_" .. ID, light.shadow.cams[1].position)
		
		shader:send("ss_proj1_" .. ID, light.shadow.cams[1].transformProj)
		shader:send("ss_proj2_" .. ID, light.shadow.cams[2].transformProj)
		shader:send("ss_proj3_" .. ID, light.shadow.cams[3].transformProj)
		
		shader:send("ss_tex1_" .. ID, light.shadow.canvases[1])
		shader:send("ss_tex2_" .. ID, light.shadow.canvases[2])
		shader:send("ss_tex3_" .. ID, light.shadow.canvases[3])
		
		shader:send("ss_color_" .. ID, light.color * light.brightness)
		
		if shader:hasUniform("ss_vec_" .. ID) then
			shader:send("ss_vec_" .. ID, light.direction)
		end
	else
		shader:send("ss_color_" .. ID, {0, 0, 0})
	end
end

return sh