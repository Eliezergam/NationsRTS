--[[
#part of the 3DreamEngine by Luke100000
settings.lua - a bunch of setter and getter to set global settings
--]]

---@type Dream
local lib = _3DreamEngine

---Sets the max count of simple light sources
---@param count number
function lib:setMaxLights(count)
	self.max_lights = count
end
function lib:getMaxLights()
	return self.max_lights
end

---Set frustum check
---@param enable boolean
function lib:setFrustumCheck(enable)
	self.frustumCheck = enable
end
function lib:getFrustumCheck()
	return self.frustumCheck
end

---Sets the distance of the lowest LOD level
---@param distance number
function lib:setLODDistance(distance)
	self.LODDistance = distance
	self.LODFactor = 1 / distance
end
function lib:getLODDistance()
	return self.LODDistance
end


--exposure
---Sets whether tone-mapping should be applied, deprecated
---@param enable boolean
---@deprecated
function lib:setExposure(enable)
	self.exposure = enable or false
end

---@deprecated
function lib:getExposure()
	return self.exposure
end

---Toggle auto exposure
---@param target number @ target average screen brightness, default 0.3 when `true`
---@param speed number @ speed of adaption, default 1.0
---@overload fun(target: boolean)
function lib:setAutoExposure(target, speed)
	if target == true then
		self:setAutoExposure(0.3, 1.0)
	elseif target then
		if not self.canvasFormats["r16f"] then
			print("Auto exposure required r16f support.")
			self:setAutoExposure()
		end
		
		self.autoExposure_enabled = true
		self.autoExposure_targetBrightness = target
		self.autoExposure_adaptionSpeed = speed
	else
		self.autoExposure_enabled = false
	end
end
function lib:getAutoExposure()
	return self.autoExposure_enabled, self.autoExposure_targetBrightness, self.autoExposure_adaptionSpeed
end

---Sets the screen gamma
---@param gamma number
function lib:setGamma(gamma)
	self.gamma = gamma
end
function lib:getGamma()
	return self.gamma
end

---Sets the Screen Space Ambient Occlusion settings
---@param samples number @ more samples result in less visible patterns/artifacts
---@param resolution number @ resolution factor of temporary canvas
---@param blur number @ strength of blur and size of occlusion
function lib:setAO(samples, resolution, blur)
	if samples then
		self.AO_enabled = true
		self.AO_quality = samples
		self.AO_resolution = resolution
		self.AO_blur = blur
	else
		self.AO_enabled = false
	end
end

---Get the state of ambient occlusion
---@return boolean, number, number @ enabled, quality, resolution
function lib:getAO()
	return self.AO_enabled, self.AO_quality, self.AO_resolution
end

---Bloom effect settings
---@param quality number @ blurring iterations
---@param resolution number @ default 0.5
---@param size number @ default 0.1
---@param strength number @ default 1.0
function lib:setBloom(quality, resolution, size, strength)
	if quality then
		self.bloom_enabled = true
		self.bloom_quality = quality
		self.bloom_resolution = resolution or 0.5
		self.bloom_size = size or 0.1
		self.bloom_strength = strength or 1.0
	else
		self.bloom_enabled = false
	end
end

---Get the state of bloom
---@return boolean, number, number, number, number @ enabled, quality, resolution, size, strength
function lib:getBloom()
	return self.bloom_enabled, self.bloom_quality, self.bloom_resolution, self.bloom_size, self.bloom_strength
end

---Depth based fog
---@param density number
---@param color DreamVec3
---@param scatter number @ Light scatter effect on sun light
function lib:setFog(density, color, scatter)
	if density then
		self.fog_enabled = true
		self.fog_density = density
		self.fog_color = color
		self.fog_scatter = scatter
	else
		self.fog_enabled = false
	end
end

---Color of the fog from the sky just above the horizon (NationsRTS): a strip
---texture with the azimuth 0..2pi along x (linear rgb). nil restores fog_color.
---@param strip Texture
function lib:setFogSky(strip)
	self.fog_sky = strip
end

---Pixel format of the linear depth canvas (NationsRTS), default "r16f". Needs a resize.
---@param format string
function lib:setDepthCanvasFormat(format)
	self.depthCanvasFormat = format
end

---Keep the ambient (sky) light of each pixel in its own canvas, so the ambient
---occlusion only darkens that part (NationsRTS). Needs init/resize.
---@param enabled boolean
function lib:setAmbientSplit(enabled)
	self.ambientSplit = enabled and true or false
end

---Game side ambient occlusion (NationsRTS): `hook(canvases, cam)` renders it
---and leaves the result in `dream.aoTexture`; `uniforms` are sent to the final shader.
---@param hook function
---@param uniforms table
function lib:setAOHook(hook, uniforms)
	self.aoHook = hook
	self.finalUniforms = uniforms
end

---Screen space bounce light in the final shader (NationsRTS, needs the ambient
---split): the final shader adds ambient * `canvas_bounce` (sent with the AO
---hook uniforms). Set before the final shader is built.
---@param enabled boolean
function lib:setBounce(enabled)
	self.bounce = enabled and true or false
end

---Motion canvas (NationsRTS, needs the ambient split): each surface writes how
---far its point moved since the last frame (rgba16f `canvases.movil`, in world
---units; a vertex module that knows the previous position sets it); meshes with
---`mesh.movil` write 10000 in red. For the game's temporal AA.
---Needs init/resize.
---@param enabled boolean
function lib:setMotionMask(enabled)
	self.motionMask = enabled and true or false
end

---Contact shadows of the sun in the final shader (NationsRTS, needs the ambient split)
---@param enabled boolean
function lib:setContactShadows(enabled)
	self.contactShadows = enabled and true or false
end

---Diffuse irradiance cubemap (E / pi, same gamma as the reflections) and BRDF
---table for the PBR sky light (NationsRTS). Set before the shaders are built.
---@param irradiance Texture
---@param brdf Texture
function lib:setIrradianceMap(irradiance, brdf)
	self.irradianceMap = irradiance
	self.brdfLUTOverride = brdf
end

---Distance in front of the camera without fog (NationsRTS)
---@param start number
function lib:setFogStart(start)
	self.fog_start = start or 0
end
function lib:getFogStart()
	return self.fog_start or 0
end

---Scale of the sun shadow depth bias (NationsRTS); 1 is the original, meant
---for 1 unit = 1 m. Read when the shaders are built (before init)
---@param scale number
function lib:setShadowBias(scale)
	self.shadowBias = scale or 1
end
function lib:getShadowBias()
	return self.shadowBias or 1
end

---Pixel format of the sun shadow maps (NationsRTS), default "r16f"
---@param format string
function lib:setShadowFormat(format)
	self.shadowFormat = format
end

---Get the state of fog
---@return boolean, number, DreamVec3, number @ enabled, density, color, scatter
function lib:getFog()
	return self.fog_enabled, self.fog_density, self.fog_color, self.fog_scatter
end

---Fog height, where min is full density and max zero density, Y-aligned
---@param min number
---@param max number
function lib:setFogHeight(min, max)
	if min then
		self.fog_min = min
		self.fog_max = max
	else
		self.fog_min = 1
		self.fog_max = -1
	end
end

---Get the height, or (1, -1) if disabled
---@return number, number  @ min and max
function lib:getFogHeight()
	return self.fog_min, self.fog_max
end

---Sets the reflection type used for reflections, "sky" uses the Sky dome and only makes sense when using an animated, custom dome. Texture can be a 2D HDRi or a CubeImage, or an 3Dream Reflection object
---@param texture Texture|DreamReflection|boolean|string
function lib:setDefaultReflection(texture)
	if texture == "sky" then
		--use sky
		self.defaultReflection = "sky"
	elseif texture == false then
		--use ambient
		self.defaultReflection = false
	elseif type(texture) == "table" and texture.class == "reflection" then
		--reflection object
		self.defaultReflection = texture
	elseif type(texture) == "userdata" and texture:getTextureType() == "cube" then
		--cubemap, wrap in reflection object
		self.defaultReflection = lib:newReflection(texture)
	elseif type(texture) == "userdata" and texture:getTextureType() == "2d" then
		--HDRI
		error("HDRI not supported, please convert to cubemap first")
	else
		error("Unknown reflection")
	end
end
function lib:getDefaultReflection()
	return self.defaultReflection
end

---Set settings for sky reflection, if "sky" is used
---@param resolution number
---@param format number
---@param lazy boolean @ Update texture over several frames to spread the load
function lib:setSkyReflectionFormat(resolution, format, lazy)
	self.sky_resolution = resolution
	self.sky_format = format
	self.sky_lazy = lazy
end
function lib:getSkyReflectionFormat()
	return self.sky_resolution, self.sky_format, self.sky_lazy
end

---Sets the sky HDRI, cubemap or just sky dome
---@param sky table @ rgb color
---@param sky boolean @ false to disable sky, use in enclosed areas
---@param sky Texture @ 2D HDRI or Cubemap
---@param sky fun(transformProj: DreamMat4, camTransform: DreamMat4) @ a custom function
---@param exposure table @ only for HDRI skies, default 1.0
function lib:setSky(sky, exposure)
	if type(sky) == "table" then
		--use constant color
		self.sky_texture = sky
	elseif not sky then
		--disable sky
		self.sky_texture = false
	elseif type(sky) == "userdata" and sky:getTextureType() == "cube" then
		--cubemap
		self.sky_texture = sky
		
		--also sets reflections
		self:setDefaultReflection(sky)
	elseif type(sky) == "userdata" and sky:getTextureType() == "2d" then
		--HDRI
		self.sky_texture = sky
		self.sky_hdri_exposure = exposure or 1.0
	elseif type(sky) == "function" then
		self.sky_texture = sky
	else
		error("Unknown sky")
	end
end
function lib:getSky()
	return self.sky_texture, self.sky_hdri_exposure
end

---Set resource loader settings
---@param threaded boolean @ load textures lazily using multithreading
function lib:setResourceLoader(threaded)
	self.textures_threaded = threaded
end
function lib:getResourceLoader()
	return self.textures_threaded
end

---Toggle mipmap generations for loaded images
---@param mode boolean
function lib:setMipmaps(mode)
	self.textures_mipmaps = mode
end
function lib:getMipmaps()
	return self.textures_mipmaps
end


--todo consider removal or improving, in its current state they are useless
---@deprecated
function lib:setGodrays(quality)
	if quality then
		self.godrays_enabled = true
		self.godrays_quality = quality
	else
		self.godrays_enabled = false
	end
end
---@deprecated
function lib:getGodrays()
	return self.godrays_enabled, self.godrays_quality
end

---Distortion is a post processing effect and will fail for everything outside the screen, therefore a margin is required, higher values produce a sharper margin towards the edges, default 2.0
---@param value number
function lib:setDistortionMargin(value)
	if value == true then
		self.distortionMargin = 2.0
	elseif value then
		self.distortionMargin = value
	else
		self.distortionMargin = false
	end
end
function lib:getDistortionMargin()
	return self.distortionMargin
end

---Default Pixel shader, if not overwritten by the material or mesh
---@param shader DreamShader
function lib:setDefaultPixelShader(shader)
	shader = lib:getShader(shader)
	assert(shader.type == "pixel", "invalid shader type")
	self.defaultPixelShader = shader
end
function lib:getDefaultPixelShader()
	return self.defaultPixelShader
end

---Default Vertex shader, if not overwritten by the material or mesh
---@param shader DreamShader
function lib:setDefaultVertexShader(shader)
	shader = lib:getShader(shader)
	assert(shader.type == "vertex", "invalid shader type")
	self.defaultVertexShader = shader
end
function lib:getDefaultVertexShader()
	return self.defaultVertexShader
end

---Default World shader, if not overwritten by the material or mesh
---@param shader DreamShader
function lib:setDefaultWorldShader(shader)
	shader = lib:getShader(shader)
	assert(shader.type == "world", "invalid shader type")
	self.defaultWorldShader = shader
end
function lib:getDefaultWorldShader()
	return self.defaultWorldShader
end

---Register a new format, see `3DreamEngine/meshFormats/*` for examples
---@param format DreamMeshFormat
---@param name string
function lib:registerMeshFormat(format, name)
	self.meshFormats[name] = format
end