#version 460

precision highp float;
precision highp int;

#extension GL_EXT_nonuniform_qualifier : require
#extension GL_GOOGLE_include_directive : require
#extension GL_NV_ray_tracing : require

// Replaced by Compiler.h
// ====== DEFINES ======

#include "../Common/Structs.glsl"

layout(binding = 0, set = 0) uniform accelerationStructureNV TLAS;
layout(binding = 3) readonly uniform UniformBufferObject { Uniform ubo; };
layout(binding = 4) readonly buffer VertexArray { float Vertices[]; };
layout(binding = 5) readonly buffer IndexArray { uint Indices[]; };
layout(binding = 6) readonly buffer MaterialArray { Material[] Materials; };
layout(binding = 7) readonly buffer OffsetArray { uvec2[] Offsets; };
layout(binding = 8) uniform sampler2D[] TextureSamplers;
layout(binding = 9) readonly buffer LightArray { Light[] Lights; };

#ifdef USE_HDR
layout(binding = 10) uniform sampler2D[] HDRs;
#endif

layout(location = 0) rayPayloadInNV RayPayload payload;
layout(location = 1) rayPayloadNV bool isShadowed;

hitAttributeNV vec2 hit;

#include "../Common/Composition.glsl"
#ifdef USE_HDR
#include "../Common/HDR.glsl"
#endif
#include "../Common/Sampling.glsl"
#include "../BSDFs/UR4BRSF.glsl"
#include "Integrators/DirectLight.glsl"

void main()
{
	uvec2 offsets = Offsets[gl_InstanceCustomIndexNV];
	uint indexOffset = offsets.x;
	uint vertexOffset = offsets.y;

	const Vertex v0 = unpack(vertexOffset + Indices[indexOffset + gl_PrimitiveID * 3 + 0]);
	const Vertex v1 = unpack(vertexOffset + Indices[indexOffset + gl_PrimitiveID * 3 + 1]);
	const Vertex v2 = unpack(vertexOffset + Indices[indexOffset + gl_PrimitiveID * 3 + 2]);

	Material material = Materials[v0.materialIndex];

	const vec3 barycentrics = vec3(1.0 - hit.x - hit.y, hit.x, hit.y);
	vec3 normal = normalize(mix(v0.normal, v1.normal, v2.normal, barycentrics));
	// face forward normal
	vec3 ffnormal = dot(normal, payload.ray.direction) <= 0.0 ? normal : normal * -1.0;
	const vec2 texCoord = mix(v0.texCoord, v1.texCoord, v2.texCoord, barycentrics);
	const vec3 worldPos = mix(v0.position, v1.position, v2.position, barycentrics);

	{
		if (material.albedoTexID >= 0)
			material.albedo.xyz *= pow(texture(TextureSamplers[material.albedoTexID], texCoord).xyz, vec3(2.2));

		if (material.metallicRoughnessTexID >= 0)
		{
			vec2 update = pow(texture(TextureSamplers[material.metallicRoughnessTexID], texCoord).zy, vec2(2.2));
			//material.metallic = update.x;
			//material.roughness = update.y;
		}

		if (material.normalmapTexID >= 0)
		{
			vec3 nrm = texture(TextureSamplers[material.normalmapTexID], texCoord).xyz;
			nrm = normalize(nrm * 2.0 - 1.0);

			// Orthonormal Basis
			vec3 UpVector = abs(ffnormal.z) < 0.999 ? vec3(0, 0, 1) : vec3(1, 0, 0);
			vec3 TangentX = normalize(cross(UpVector, ffnormal));
			vec3 TangentY = cross(ffnormal, TangentX);

			nrm = TangentX * nrm.x + TangentY * nrm.y + ffnormal * nrm.z;

			normal = normalize(nrm);
			ffnormal = dot(normal, payload.ray.direction) <= 0.0 ? normal : normal * -1.0;
		}
	}

	payload.worldPos = worldPos;
	payload.normal = normal;
	payload.ffnormal = ffnormal;

	seed = tea(gl_LaunchIDNV.y * gl_LaunchSizeNV.x + gl_LaunchIDNV.x, ubo.frame);

	// vec3 hit = gl_WorldRayOriginNV + gl_WorldRayDirectionNV * gl_HitTNV;

	// Replaced by Compiler.h
	// ====== INTEGRATOR ======
}
