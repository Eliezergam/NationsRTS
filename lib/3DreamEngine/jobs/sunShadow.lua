local job = { }

---@type Dream
local lib = _3DreamEngine

local lazyMapping = { 1, 2, 1, 2, 1, 3 }

--NationsRTS: side planes of the orthographic shadow camera, normalized
local function normalizedFrustumPlanes(cam)
	local planes = lib:getFrustumPlanes(cam.transformProj)
	for i = 1, 4 do
		local p = planes[i]
		local l = math.sqrt(p[1] * p[1] + p[2] * p[2] + p[3] * p[3])
		if l > 0 then
			p[1], p[2], p[3], p[4] = p[1] / l, p[2] / l, p[3] / l, p[4] / l
		end
	end
	cam.planes = planes
end

function job:init()
	self.stencils = { }
end

function job:queue()
	--shadows
	for d, s in ipairs(lib.lighting) do
		if s.shadow and s.active and s.shadow.typ == "sun" then
			lib:addOperation("sunShadow", s)
		end
	end
end

function job:execute(light)
	--create new canvases if necessary
	if not light.shadow.canvases then
		light.shadow.canvases = { }
		light.shadow.cams = { }
		light.lastCascade = 0
	end
	
	local normal = light.direction
	--NationsRTS: center of the cascades (default, the camera), see shadow:setCenter
	local position = light.shadow.center or lib.camera.position
	
	light.lastCascade = light.lastCascade % #lazyMapping + 1
	
	for cascade = light.shadow.lazy and lazyMapping[light.lastCascade] or 1, light.shadow.lazy and lazyMapping[light.lastCascade] or 3 do
		local stepSize = light.shadow.refreshStepSize * 2.3 ^ (cascade - 1)
		
		local shadowCam = light.shadow.cams[cascade]
		--NationsRTS: depth range of the shadow cameras (shadow.depthRange, default 100 units)
		local depthRange = light.shadow.depthRange or 100
		local radius = light.shadow.cascadeDistance / 2 * (light.shadow.cascadeFactor ^ (cascade - 1))
		if not shadowCam or (position - shadowCam.position):lengthSquared() > stepSize or (normal - shadowCam.normal):lengthSquared() > 0 or shadowCam.radius ~= radius or shadowCam.depthRange ~= depthRange then
			--create shadow camera
			if not shadowCam then
				light.shadow.cams[cascade] = lib:newCamera()
				shadowCam = light.shadow.cams[cascade]
				--NationsRTS: cull casters outside the cascade box (the original drew
				--the whole scene in every cascade: ~4900 draws per frame in the
				--warehouse). What is outside the box is not rasterized anyway.
				--Planes normalized, so the test is in world units.
				shadowCam.noFrustumCheck = false
				shadowCam.forceFrustumCheck = true
				shadowCam.updateFrustumPlanes = normalizedFrustumPlanes
				shadowCam.sun = true
			end
			
			local r = radius
			local n = 1.0
			local f = depthRange
			shadowCam.radius = radius
			shadowCam.depthRange = depthRange
			
			--camera orientation
			shadowCam.position = position
			shadowCam.normal = normal
			shadowCam.transform = lib:lookAt(shadowCam.position + shadowCam.normal * (f * 0.5), shadowCam.position, lib.vec3(0.0, 1.0, 0.0))
			shadowCam.rendered = false
			
			--orthographic projected multiplied by the cameras view matrix
			local a1 = 1 / r
			local a6 = -a1
			local a11 = -2 / (f - n)
			local a12 = -(f + n) / (f - n)
			
			local b = shadowCam.transform
			shadowCam.transformProj = lib.mat4({
				a1 * b[1], a1 * b[2], a1 * b[3], a1 * b[4],
				a6 * b[5], a6 * b[6], a6 * b[7], a6 * b[8],
				a11 * b[9], a11 * b[10], a11 * b[11], a11 * b[12] + a12,
				0.0, 0.0, 0.0, 1.0,
			})
			
			--generate canvas
			if not light.shadow.canvases[cascade] then
				light.shadow.canvases[cascade] = love.graphics.newCanvas(light.shadow.resolution, light.shadow.resolution,
						--NationsRTS: r32f (with r16f the step near the ground was ~24 cm and the ground got shadow acne)
						{ format = lib.shadowFormat or "r16f",
						  readable = true,
						  msaa = 0,
						  type = "2d" })
			end
		end
		
		local canvases = { light.shadow.canvases[cascade] }
		
		--static shadow
		if not shadowCam.rendered or not light.shadow.static then
			local dynamic
			if light.shadow.static then
				dynamic = false
			end
			
			lib:render(shadowCam, canvases, dynamic, true, light.blacklist)
			
			--smooth lighting
			if light.shadow.smooth then
				local blurStrength = 30.0 * light.size / light.shadow.cascadeFactor ^ (cascade - 1)
				local iterations = math.ceil(blurStrength)
				lib:blurCanvas(light.shadow.canvases[cascade], blurStrength / iterations, iterations, { true, false, false, false })
			end
		end
		
		shadowCam.rendered = true
	end
end

return job