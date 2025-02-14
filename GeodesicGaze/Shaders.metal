//
//  Shaders.metal
//  MultiCamDemo
//
//  Created by Trevor Gravely on 7/16/24.
//

#include <metal_stdlib>

#include "Utilities.h"
#include "MathFunctions.h"
#include "Physics.h"

using namespace metal;

// TODO: fix status code overlaps with EMITTED_FROM_BLACK_HOLE

#define SUCCESS_BACK_TEXTURE 5
#define SUCCESS_FRONT_TEXTURE 4
#define OUTSIDE_FOV 1
#define ERROR 2
#define VORTICAL 10

#define FULL_FOV_MODE 0
#define ACTUAL_FOV_MODE 1

struct LenseTextureCoordinateResult {
    float2 coord;
    int status;
};

struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

struct Uniforms {
    int frontTextureWidth;
    int frontTextureHeight;
    int backTextureWidth;
    int backTextureHeight;
    int mode;
    int spacetimeMode;
    int isBlackHoleInFront;
    float vcWidthToViewWidth;
    float vcEdgeInViewTextureCoords;
    int isPipEnabled;
};

struct PreComputeUniforms {
    int mode;
};

struct FilterParameters {
    int spaceTimeMode;
    int sourceMode;
    float d;
    float a;
    float thetas;
    int schwarzschildMode;
};

float flipTextureCoord(float coord) {
    float Deltax = 0.5 - coord;
    return 0.5 + Deltax;
}

float3 sampleYUVTexture(texture2d<float, access::sample> YTexture,
                        texture2d<float, access::sample> UVTexture,
                        float2 texCoord) {
    // The sampler to be used for obtaining pixel colors
    constexpr sampler textureSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    
    float y = YTexture.sample(textureSampler, texCoord).r;
    float2 uv = UVTexture.sample(textureSampler, texCoord).rg;
    
    return yuvToRgb(y, uv.x, uv.y);
}


float2 pixelToScreen(float2 pixelCoords) {
    float base = 0.04;
    float rcrit = 300.0;
    float alpha = 1000.0;
    int n = 1;
    
    float r = sqrt(pixelCoords.x * pixelCoords.x + pixelCoords.y * pixelCoords.y);
    
    if (r < rcrit) {
        return base * pixelCoords;
    }
    
    return ((1.0 / alpha) * pow(r - rcrit, n) + base) * pixelCoords;
    // return 0.2 * pixelCoords;
}

float distortb(float bc, float bouter, float b) {
    assert(bc < bouter);
    
    float slope = 0.5;
    float yint = bc - slope * bc;
    float yshift = yint + slope * bouter;
    float xshift = bouter;

    if (b < bc) {
        return b;
    } else if (b < bouter) {
        return yint + slope * b;
    } else {
        return (b - xshift) * (b - xshift) + yshift;
    }
}

LenseTextureCoordinateResult schwarzschildLenseTextureCoordinateScreenMode(float2 inCoord, int sourceMode, float M, float d) {
    LenseTextureCoordinateResult result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    float rs = d;
    float ro = rs;
    
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    float2 relativePixelCoords = pixelCoords - center;
    
    // Notice the swapping
    float imgx = relativePixelCoords.y;
    float imgy = relativePixelCoords.x;
    
    float psi = atan2(imgy, imgx);
    float rho = sqrt(imgx * imgx + imgy * imgy);
    
    // The diameter of the critical curve as a percentage of the height
    float criticalCurveDiameterPct = 0.05;
    
    float criticalCurveDiameterInPixelUnits = criticalCurveDiameterPct * backTextureWidth;
    
    // Once the size of the critical curve on the screen is chosen, this fixes
    // the conversion factor from pixel units on the screen to physical distances
    // since the critical curve has a radius of 3 sqrt(3) M.
    float bc = 3.0 * sqrt(3.0) * M;
    float pixelToPhysicalDistance = bc / criticalCurveDiameterInPixelUnits;
    
    float b = (1.0 / 2.0) * rho * pixelToPhysicalDistance;
    b = distortb(bc, 1.1 * bc, b);
    
    SchwarzschildLenseResult lenseResult = schwarzschildLense(M, ro, rs, b);
    if (lenseResult.status == FAILURE) {
        result.status = ERROR;
        return result;
    } else if (lenseResult.status == EMITTED_FROM_BLACK_HOLE) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    
    // This angle is already normalized to lie between 0 and 2 pi.
    float phiS = lenseResult.phif;
    
    // There is a measure zero set of screen locations that eject "vertically" from the black hole
    // such that they never intersect our screens.
    if (fEqual(phiS, M_PI_F / 2.0) || fEqual(phiS, 3.0 * M_PI_F / 2.0)) {
        result.status = OUTSIDE_FOV;
        return result;
    }
    
    float btilde;
    bool isRearFacing;
    
    float oneTwoBdd = M_PI_F / 2.0;
    float threeFourBdd = 3.0 * M_PI_F / 2.0;
    // quadrant I or IV
    if ((0.0 <= phiS && phiS <= oneTwoBdd) ||
        (threeFourBdd <= phiS && phiS <= 2.0 * M_PI_F)) {
        btilde = (ro / 2.0) * tan(phiS);
        isRearFacing = false;
    } else { // quadrant II or III
        // This minus sign ensures that as phiS goes from pi / 2 to
        // 3 pi / 2, btilde goes from positive to negative (plot -tan over this range).
        // This is the correct behavior since btilde should be positive in the 2nd quadrant
        // and negative in the 3rd quadrant.
        btilde = -1.0 * (ro / 2.0) * tan(phiS);
        isRearFacing = true;
    }
    
    // This has a sign (inherited from btilde), as it should. Indicates whether
    // we move up or down on the ray of constant psi.
    pixelToPhysicalDistance = 50.0 * pixelToPhysicalDistance;
    float rhotilde = 2.0 * (1.0 / pixelToPhysicalDistance) * btilde;
    
    // float minPixelRadius = 1080.0 / 2.0;
    // float scale = 0.1;
    // rhotilde = minPixelRadius * (2.0 / M_PI_F) * atan(scale * rhotilde);

    float imgxtilde = rhotilde * cos(psi);
    float imgytilde = rhotilde * sin(psi);
    
    float2 transformedRelativePixelCoords = float2(imgytilde, imgxtilde);
    float2 transformedPixelCoords = transformedRelativePixelCoords + center;
    float2 transformedTexCoord = transformedPixelCoords / float2(backTextureWidth, backTextureHeight);
    

    // Ensure that the texture coordinate is inbounds
    if (transformedTexCoord.x < 0.0 || 1.0 < transformedTexCoord.x ||
        transformedTexCoord.y < 0.0 || 1.0 < transformedTexCoord.y) {
        result.status = OUTSIDE_FOV;
        return result;
    }

    result.coord = transformedTexCoord;
    result.status = (isRearFacing) ? SUCCESS_BACK_TEXTURE : SUCCESS_FRONT_TEXTURE;
    return result;
}

LenseTextureCoordinateResult schwarzschildLenseTextureCoordinate(float2 inCoord, int sourceMode, float M, float d) {
    LenseTextureCoordinateResult result;
    
    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    // We let rs and ro be large in this set up.
    // This will allow for the usage of an approximation to the
    // elliptic integrals during lensing.
    float rs = d;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane
    float lengthPerPixel = 0.0014;
    float2 imagePlaneCoords = lengthPerPixel * relativePixelCoords;

    // Obtain the polar coordinates of this image plane location
    float f = 4.25;
    float rho = sqrt(imagePlaneCoords.x * imagePlaneCoords.x + imagePlaneCoords.y * imagePlaneCoords.y);
    
    float varphi = atan2(rho, f);
    float b = ro * sin(varphi);
    
    // Notice the swapping ... the first texture coordinate is vertical
    float psi = atan2(imagePlaneCoords.x, imagePlaneCoords.y);

    SchwarzschildLenseResult lenseResult = schwarzschildLense(M, ro, rs, b);
    if (lenseResult.status == FAILURE) {
        result.status = ERROR;
        return result;
    } else if (lenseResult.status == EMITTED_FROM_BLACK_HOLE) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    float varphitilde = lenseResult.varphitilde;
    bool ccw = lenseResult.ccw;
    
    if (sourceMode == FULL_FOV_MODE) {
        float3 vsSpherical = float3(rs, M_PI_F / 2.0, lenseResult.phif);
        float3 vsCartesian = sphericalToCartesian(vsSpherical);
        
        // Rotation by psi about the x-axis
        // Aligns the plane of motion with the equatorial plane
        float3 r1 = float3(1.0, 0.0,        0.0);
        float3 r2 = float3(0.0, cos(psi),   -1.0 * sin(psi));
        float3 r3 = float3(0.0, sin(psi),   cos(psi));

        // Matrix multiplication by the matrix with rows r1-3
        float3 vsHatCartesian = float3(dot(r1, vsCartesian),
                                       dot(r2, vsCartesian),
                                       dot(r3, vsCartesian));
        
        // The spherical coordinates of ray's intersection with the source sphere
        // in the fixed, reference frame.
        float3 vsHatSpherical = cartesianToSpherical(vsHatCartesian);
        
        float phifNormalized = normalizeAngle(vsHatSpherical.z);
        float thetaf = vsHatSpherical.y;
        
        float oneTwoBdd = M_PI_F / 2.0;
        float threeFourBdd = 3.0 * M_PI_F / 2.0;
        
        float v = thetaf / M_PI_F;
        float u = 0.0;
        
        // If in quadrant I
        if (0.0 <= phifNormalized && phifNormalized <= oneTwoBdd) {
            u = 0.5 + 0.5 * (phifNormalized / oneTwoBdd);
            result.status = SUCCESS_FRONT_TEXTURE;
        } else if (threeFourBdd <= phifNormalized && phifNormalized <= 2.0 * M_PI_F) { // quadrant IV
            u = 0.5 * ((phifNormalized - threeFourBdd) / (2.0 * M_PI_F - threeFourBdd));
            result.status = SUCCESS_FRONT_TEXTURE;
        } else { // II or III
            u = (phifNormalized - oneTwoBdd) / (threeFourBdd - oneTwoBdd);
            result.status = SUCCESS_BACK_TEXTURE;
        }
        // NOTICE THAT u and v are swapped! Same reason as before.
        float2 transformedTexCoord = float2(flipTextureCoord(v), flipTextureCoord(u));
        
        result.coord = transformedTexCoord;

        return result;
    }

    float rhotilde = f * tan(varphitilde);
    // Again, the swapping
    float2 transformedImagePlaneCoords = (ccw ? -1.0 : 1.0) * float2(rhotilde * sin(psi), rhotilde * cos(psi));
    
    float2 transformedRelativePixelCoords = transformedImagePlaneCoords / lengthPerPixel;
    float2 transformedPixelCoords = transformedRelativePixelCoords + center;
    float2 transformedTexCoord = transformedPixelCoords / float2(backTextureWidth, backTextureHeight);

    // Ensure that the texture coordinate is inbounds
    if (transformedTexCoord.x < 0.0 || 1.0 < transformedTexCoord.x ||
        transformedTexCoord.y < 0.0 || 1.0 < transformedTexCoord.y) {
        result.status = OUTSIDE_FOV;
        return result;
    }

    result.coord = transformedTexCoord;
    result.status = SUCCESS;
    return result;
}

LenseTextureCoordinateResult schwarzschildLenseTextureCoordinateOther(float2 inCoord, int sourceMode, float M, float d) {
    LenseTextureCoordinateResult result;
    
    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    // We let rs and ro be large in this set up.
    // This will allow for the usage of an approximation to the
    // elliptic integrals during lensing.
    float rs = d;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane
    float lengthPerPixel = 0.2;
    float2 imagePlaneCoords;
    if (sourceMode == FULL_FOV_MODE) {
        imagePlaneCoords = pixelToScreen(relativePixelCoords);
    } else {
        imagePlaneCoords = lengthPerPixel * relativePixelCoords;
    }

    // Obtain the polar coordinates of this image plane location
    float b = length(imagePlaneCoords);
    // Notice the swapping ... the first texture coordinate is vertical
    float psi = atan2(imagePlaneCoords.x, imagePlaneCoords.y);

    SchwarzschildLenseResult lenseResult = schwarzschildLense(M, ro, rs, b);
    if (lenseResult.status == FAILURE) {
        result.status = ERROR;
        return result;
    } else if (lenseResult.status == EMITTED_FROM_BLACK_HOLE) {
        result.status = EMITTED_FROM_BLACK_HOLE;
        return result;
    }
    float varphitilde = lenseResult.varphitilde;
    bool ccw = lenseResult.ccw;
    
    if (sourceMode == FULL_FOV_MODE) {
        float3 vsSpherical = float3(rs, M_PI_F / 2.0, lenseResult.phif);
        float3 vsCartesian = sphericalToCartesian(vsSpherical);
        
        // Rotation by psi about the x-axis
        // Aligns the plane of motion with the equatorial plane
        float3 r1 = float3(1.0, 0.0,        0.0);
        float3 r2 = float3(0.0, cos(psi),   -1.0 * sin(psi));
        float3 r3 = float3(0.0, sin(psi),   cos(psi));

        // Matrix multiplication by the matrix with rows r1-3
        float3 vsHatCartesian = float3(dot(r1, vsCartesian),
                                       dot(r2, vsCartesian),
                                       dot(r3, vsCartesian));
        
        // The spherical coordinates of ray's intersection with the source sphere
        // in the fixed, reference frame.
        float3 vsHatSpherical = cartesianToSpherical(vsHatCartesian);
        
        float phifNormalized = normalizeAngle(vsHatSpherical.z);
        float thetaf = vsHatSpherical.y;
        
        float oneTwoBdd = M_PI_F / 2.0;
        float threeFourBdd = 3.0 * M_PI_F / 2.0;
        
        float v = thetaf / M_PI_F;
        float u = 0.0;
        
        // If in quadrant I
        if (0.0 <= phifNormalized && phifNormalized <= oneTwoBdd) {
            u = 0.5 + 0.5 * (phifNormalized / oneTwoBdd);
            result.status = SUCCESS_FRONT_TEXTURE;
        } else if (threeFourBdd <= phifNormalized && phifNormalized <= 2.0 * M_PI_F) { // quadrant IV
            u = 0.5 * ((phifNormalized - threeFourBdd) / (2.0 * M_PI_F - threeFourBdd));
            result.status = SUCCESS_FRONT_TEXTURE;
        } else { // II or III
            u = (phifNormalized - oneTwoBdd) / (threeFourBdd - oneTwoBdd);
            result.status = SUCCESS_BACK_TEXTURE;
        }
        // NOTICE THAT u and v are swapped! Same reason as before.
        // TODO: understand why the flips are needed ... probably take LOS -> -LOS
        float2 transformedTexCoord = float2(flipTextureCoord(v), flipTextureCoord(u));
        
        result.coord = transformedTexCoord;

        return result;
    }

    // Unwind through the inverse transformation to texture coordinates.
    // Note that because ro = rs, we don't need to worry about the front-facing
    // camera.
    float btilde = ro * sin(varphitilde);
    
    // Again, the swapping
    float2 transformedImagePlaneCoords = (ccw ? -1.0 : 1.0) * float2(btilde * sin(psi), btilde * cos(psi));
    
    float2 transformedRelativePixelCoords = transformedImagePlaneCoords / lengthPerPixel;
    float2 transformedPixelCoords = transformedRelativePixelCoords + center;
    float2 transformedTexCoord = transformedPixelCoords / float2(backTextureWidth, backTextureHeight);

    // Ensure that the texture coordinate is inbounds
    if (transformedTexCoord.x < 0.0 || 1.0 < transformedTexCoord.x ||
        transformedTexCoord.y < 0.0 || 1.0 < transformedTexCoord.y) {
        result.status = OUTSIDE_FOV;
        return result;
    }

    result.coord = transformedTexCoord;
    result.status = SUCCESS;
    return result;
}

LenseTextureCoordinateResult kerrLenseTextureCoordinate(float2 inCoord, int sourceMode, float d, float a) {
    LenseTextureCoordinateResult result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;

    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float M = 1.0;
    float thetas = M_PI_F / 2.0;
    float rs = d;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float lengthPerPixel = 0.2;
    float2 imagePlaneCoords;
    if (sourceMode == FULL_FOV_MODE) {
        imagePlaneCoords = pixelToScreen(relativePixelCoords);
    } else {
        imagePlaneCoords = lengthPerPixel * relativePixelCoords;
    }

    // NOTICE THAT y and x are swapped! The first index into inCoord is
    // the up and down direction.
    float alpha = imagePlaneCoords.y;
    float beta = imagePlaneCoords.x;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    // We don't currently handle the case of vortical geodesics
    if (eta <= 0.0) {
        result.status = VORTICAL;
        return result;
    }
    
    // Do the actual lensing. The result is a final theta and phi.
    KerrLenseResult kerrLenseResult = kerrLense(a, M, thetas, nuthetas, ro, rs, eta, lambda);
    if (kerrLenseResult.status != SUCCESS) {
        result.status = ERROR;
        return result;
    }
    float phif = kerrLenseResult.phif;
    float thetaf = acos(kerrLenseResult.costhetaf);
    
    if (sourceMode == FULL_FOV_MODE) {
        float3 rotatedSphericalCoordinates = rotateSphericalCoordinate(float3(rs, thetas, 0.0),
                                                                       float3(ro, thetaf, phif));
        
        float phifNormalized = normalizeAngle(rotatedSphericalCoordinates.z);
        thetaf = rotatedSphericalCoordinates.y;
        
        float oneTwoBdd = M_PI_F / 2.0;
        float threeFourBdd = 3.0 * M_PI_F / 2.0;
        
        float v = thetaf / M_PI_F;
        float u = 0.0;
        
        // If in quadrant I
        if (0.0 <= phifNormalized && phifNormalized <= oneTwoBdd) {
            u = 0.5 + 0.5 * (phifNormalized / oneTwoBdd);
            result.status = SUCCESS_FRONT_TEXTURE;
        } else if (threeFourBdd <= phifNormalized && phifNormalized <= 2.0 * M_PI_F) { // quadrant IV
            u = 0.5 * ((phifNormalized - threeFourBdd) / (2.0 * M_PI_F - threeFourBdd));
            result.status = SUCCESS_FRONT_TEXTURE;
        } else { // II or III
            u = (phifNormalized - oneTwoBdd) / (threeFourBdd - oneTwoBdd);
            result.status = SUCCESS_BACK_TEXTURE;
        }
        // NOTICE THAT u and v are swapped! Same reason as before.
        float2 transformedTexCoord = float2(v, u);
        
        result.coord = transformedTexCoord;
        return result;
    }
    
    // Obtain the corresponding values of eta_flat, lambda_flat.
    FlatSpaceEtaLambdaResult flatSpaceEtaLambdaResult = flatSpaceEtaLambda(rs, thetas, 0, ro, thetaf, phif);
    if (flatSpaceEtaLambdaResult.status != SUCCESS) {
        result.status = ERROR;
        return result;
    }
    float etaflat = flatSpaceEtaLambdaResult.etaflat;
    float lambdaflat = flatSpaceEtaLambdaResult.lambdaflat;
    float pthetaSign = flatSpaceEtaLambdaResult.uthetaSign;
    
    // Map back to screen coordinates
    float alphaflat = -1.0 * lambdaflat / sin(thetas);
    float termUnderRadical = etaflat - lambdaflat * lambdaflat * (1.0 / tan(thetas)) * (1.0 / tan(thetas));
    if (termUnderRadical < 0.0) {
        result.status = ERROR;
        return result;
    }
    float betaflat = pthetaSign * sqrt(termUnderRadical);
    
    // Unwind through the texture -> screen coordinate mappings
    float2 transformedImagePlaneCoords = float2(betaflat, alphaflat);
    float2 transformedRelativePixelCoords = transformedImagePlaneCoords / lengthPerPixel;
    float2 transformedPixelCoords = transformedRelativePixelCoords + center;
    float2 transformedTexCoord = transformedPixelCoords / float2(backTextureWidth, backTextureHeight);
    
    // Ensure that the texture coordinate is inbounds
    if (transformedTexCoord.x < 0.0 || 1.0 < transformedTexCoord.x ||
        transformedTexCoord.y < 0.0 || 1.0 < transformedTexCoord.y) {
        result.status = OUTSIDE_FOV;
        return result;
    }
    
    result.coord = transformedTexCoord;
    result.status = SUCCESS;
    return result;
}

LenseTextureCoordinateResult flatspaceLenseTextureCoordinate(float2 inCoord, int sourceMode) {
    return schwarzschildLenseTextureCoordinate(inCoord, sourceMode, 0.0, 1000.0);
}

vertex VertexOut vertexShader(uint vertexID [[vertex_id]]) {
    float4 positions[4] = {
        float4(-1.0,  1.0, 0.0, 1.0),
        float4( 1.0,  1.0, 0.0, 1.0),
        float4(-1.0, -1.0, 0.0, 1.0),
        float4( 1.0, -1.0, 0.0, 1.0)
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 1.0),
        float2(1.0, 0.0)
    };
    
    VertexOut out;
    out.position = positions[vertexID];
    out.texCoord = texCoords[vertexID];
    return out;
}

// Convert from origin top left, +x to the right, +y down coords to
// origin top right, +y to the left, +x down.
float2 fromStandardTextureCoordsToAppleTextureCoords(float2 inCoords) {
    return float2(inCoords.y, 1.0 - inCoords.x);
}

float2 fromAppleTextureCoordsToStandardTextureCoords(float2 inCoords) {
    return float2(1.0 - inCoords.y, inCoords.x);
}

float2 getPipCoord(float2 pipOrigin, float pipHeight, float pipWidth, float2 coord) {
    float2 displacement = coord - pipOrigin;
    float2 renormalizedCoord = float2(displacement.x / pipWidth, displacement.y / pipHeight);
    
    return renormalizedCoord;
}

/*
 * To avoid computing the same lensing map every frame, we compute once
 * and store the result in a look-up table (LUT). The LUT is then passed
 * to the fragment shader on subsequent render passes (per frame updates)
 * and sampled.
 */
kernel void precomputeLut(texture2d<float, access::write> lut   [[texture(0)]],
                          constant FilterParameters &uniforms   [[buffer(0)]],
                          device float3* matrix                 [[buffer(1)]],
                          constant uint& width                  [[buffer(2)]],
                          uint2 gid [[thread_position_in_grid]]) {
    // This is normalizing to texture coordinate between 0 and 1
    float2 originalCoord = float2(gid) / float2(lut.get_width(), lut.get_height());
    
    // This is the texture coordinate that places us on the beta axis
    if (fEqual(0.5, originalCoord.y)) {
        // This is spacing between the discretized values of the texture coordinate
        float minSpacing = 1.0 / lut.get_height();
    
        // Increment by 1/2 this min spacing to maintain monotonicity
        originalCoord.y = originalCoord.y + minSpacing;
    }
    
    LenseTextureCoordinateResult result;
    if (uniforms.spaceTimeMode == 0) {
        result = flatspaceLenseTextureCoordinate(originalCoord, uniforms.sourceMode);
    } else if (uniforms.spaceTimeMode == 1) {
        if (uniforms.schwarzschildMode == 0) {
            result = schwarzschildLenseTextureCoordinateScreenMode(originalCoord, uniforms.sourceMode, 1.0, 1000.0);
        } else {
            result = schwarzschildLenseTextureCoordinate(originalCoord, uniforms.sourceMode, 1.0, 200.0);
        }
    } else if (uniforms.spaceTimeMode == 2) {
        result = kerrLenseTextureCoordinate(originalCoord, uniforms.sourceMode, uniforms.d, uniforms.a);
    } else {
        assert(false);
    }

    // Need to pass the status code within the look-up table. We do so in the
    // zw components with binary strings (00, 01, 10, 11)
    if (uniforms.sourceMode == FULL_FOV_MODE) {
        if (result.status == SUCCESS_BACK_TEXTURE) {
            lut.write(float4(result.coord, 0.0, 0.0), gid); // 00
        }
        if (result.status == SUCCESS_FRONT_TEXTURE) {
            lut.write(float4(result.coord, 0.0, 1.0), gid); // 01
        }
        if (result.status == ERROR) {
            lut.write(float4(0.0, 0.0, 1.0, 0.0), gid); // 10
        }
        if (result.status == EMITTED_FROM_BLACK_HOLE) {
            lut.write(float4(0.0, 0.0, 1.0, 1.0), gid); // 11
        }
        if (result.status == VORTICAL) {
            lut.write(float4(0.0, 0.0, 0.5, 0.5), gid);
        }
        if (result.status == OUTSIDE_FOV) {
            lut.write(float4(0.0, 0.0, 0.5, 0.5), gid);
        }
    }
    
    if (uniforms.sourceMode == ACTUAL_FOV_MODE) {
        if (result.status == SUCCESS) {
            lut.write(float4(result.coord, 0.0, 0.0), gid);
        }
        if (result.status == ERROR) {
            lut.write(float4(0.0, 0.0, 0.0, 1.0), gid);
        }
        if (result.status == OUTSIDE_FOV) {
            lut.write(float4(0.0, 0.0, 1.0, 0.0), gid);
        }
        if (result.status == EMITTED_FROM_BLACK_HOLE) {
            lut.write(float4(0.0, 0.0, 1.0, 1.0), gid);
        }
        if (result.status == VORTICAL) {
            lut.write(float4(0.0, 0.0, 0.5, 0.5), gid); // 11
        }
    }
}


fragment float4 preComputedFragmentShader(VertexOut in [[stage_in]],
                                          texture2d<float, access::sample> frontYTexture [[texture(0)]],
                                          texture2d<float, access::sample> frontUVTexture [[texture(1)]],
                                          texture2d<float, access::sample> backYTexture [[texture(2)]],
                                          texture2d<float, access::sample> backUVTexture [[texture(3)]],
                                          texture2d<float, access::sample> lutTexture [[texture(4)]],
                                          texture2d<uint, access::sample> mmaLutTexture [[texture(5)]],
                                          constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    
    /*
    float aRatio = 1920.0 / 1080.0;
    float pipHeight = 0.2;
    float pipWidth = pipHeight * aRatio;

    float edgeSpacing = 0.1;
    
    float2 backPipOrigin = float2(edgeSpacing, 1.0 - pipHeight - edgeSpacing);
    float2 frontPipOrigin = float2(edgeSpacing, edgeSpacing);

    float2 backPipCoord = getPipCoord(backPipOrigin, pipWidth, pipHeight, in.texCoord);
    if (    0.0 < backPipCoord.x && backPipCoord.x < 1.0
        &&  0.0 < backPipCoord.y && backPipCoord.y < 1.0) {
        float3 rgb = sampleYUVTexture(backYTexture, backUVTexture, backPipCoord);
        return float4(rgb, 1.0);
    }
    
    float2 frontPipCoord = getPipCoord(frontPipOrigin, pipHeight, pipWidth, in.texCoord);
    if (    0.0 < frontPipCoord.x && frontPipCoord.x < 1.0
        &&  0.0 < frontPipCoord.y && frontPipCoord.y < 1.0) {
        float3 rgb = sampleYUVTexture(frontYTexture, frontUVTexture, frontPipCoord);
        return float4(rgb, 1.0);
    }
    */
    // float vcWidthToViewWidth = 0.821;
    // float vcEdgeInViewTextureCoords = 0.0893;

    if (uniforms.isPipEnabled == 1) {
        float vcWidthToViewWidth = uniforms.vcWidthToViewWidth;
        float vcEdgeInViewTextureCoords = uniforms.vcEdgeInViewTextureCoords;
        
        float vcPipWidth = 0.2;

        // Work in vc texture coordinates since that's what matches to the visible screen
        float verticalMargin = 0.1;
        float horizontalMargin = 0.05;
        float2 vcTextureCoordOfBackPipOrigin   = float2(horizontalMargin                    , verticalMargin);
        float2 vcTextureCoordOfFrontPipOrigin  = float2(1.0 - horizontalMargin - vcPipWidth , verticalMargin);
        
        // Because the frame is already 1920 x 1080 the aspect ratio in
        // texture coordinate dimensions is just 1 : 1
        float pipWidth  = vcPipWidth * vcWidthToViewWidth;
        float pipHeight = pipWidth;
        
        float2 viewTextureCoordOfBackPipOrigin;
        viewTextureCoordOfBackPipOrigin.x = vcEdgeInViewTextureCoords + vcWidthToViewWidth * vcTextureCoordOfBackPipOrigin.x;
        viewTextureCoordOfBackPipOrigin.y = vcTextureCoordOfBackPipOrigin.y;
        
        float2 viewTextureCoordOfFrontPipOrigin;
        viewTextureCoordOfFrontPipOrigin.x = vcEdgeInViewTextureCoords + vcWidthToViewWidth * vcTextureCoordOfFrontPipOrigin.x;
        viewTextureCoordOfFrontPipOrigin.y = vcTextureCoordOfFrontPipOrigin.y;
        
        float2 inViewStandardTextureCoords = fromAppleTextureCoordsToStandardTextureCoords(in.texCoord);

        float2 inBackPipStandardTextureCoords = getPipCoord(viewTextureCoordOfBackPipOrigin,
                                                            pipHeight,
                                                            pipWidth,
                                                            inViewStandardTextureCoords);
        float2 inBackPipAppleTextureCoords = fromStandardTextureCoordsToAppleTextureCoords(inBackPipStandardTextureCoords);
        if (    0.0 < inBackPipAppleTextureCoords.x && inBackPipAppleTextureCoords.x < 1.0
            &&  0.0 < inBackPipAppleTextureCoords.y && inBackPipAppleTextureCoords.y < 1.0) {
            float3 rgb = sampleYUVTexture(backYTexture, backUVTexture, inBackPipAppleTextureCoords);
            return float4(rgb, 1.0);
        }
        
        float2 inFrontPipStandardTextureCoords = getPipCoord(viewTextureCoordOfFrontPipOrigin,
                                                             pipHeight,
                                                             pipWidth,
                                                             inViewStandardTextureCoords);
        float2 inFrontPipAppleTextureCoords = fromStandardTextureCoordsToAppleTextureCoords(inFrontPipStandardTextureCoords);
        if (    0.0 < inFrontPipAppleTextureCoords.x && inFrontPipAppleTextureCoords.x < 1.0
            &&  0.0 < inFrontPipAppleTextureCoords.y && inFrontPipAppleTextureCoords.y < 1.0) {
            float3 rgb = sampleYUVTexture(frontYTexture, frontUVTexture, inFrontPipAppleTextureCoords);
            return float4(rgb, 1.0);
        }
    }

    float4 lutSample;
    if (uniforms.spacetimeMode == 2) {
        uint4 lutSampleUint = mmaLutTexture.sample(s, float2(in.texCoord.y, in.texCoord.x));
        lutSample = float4(lutSampleUint) / 65535.0;
    } else {
        lutSample = lutTexture.sample(s, in.texCoord);
    }
    
    float2 transformedTexCoord = lutSample.xy;
    float2 statusCode = lutSample.zw;
    
    bool isBlackHoleInFront = uniforms.isBlackHoleInFront;
    
    if (fEqual(statusCode[0], 10.0) && fEqual(statusCode[1], 10.0)) {
        return float4(1,0,0,1);
    }
    
    if (uniforms.mode == FULL_FOV_MODE) {
        if (fEqual(statusCode[0], 0.0) && fEqual(statusCode[1], 0.0)) {
            float3 rgb;
            if (isBlackHoleInFront) {
                rgb = sampleYUVTexture(backYTexture, backUVTexture, transformedTexCoord);
            } else {
                rgb = sampleYUVTexture(frontYTexture, frontUVTexture, transformedTexCoord);
            }
            return float4(rgb, 1.0);
        } else if (fEqual(statusCode[0], 0.0) && fEqual(statusCode[1], 1.0)) {
            float3 rgb;
            if (isBlackHoleInFront) {
                rgb = sampleYUVTexture(frontYTexture, frontUVTexture, transformedTexCoord);
            } else {
                rgb = sampleYUVTexture(backYTexture, backUVTexture, transformedTexCoord);
            }
            return float4(rgb, 1.0);
        } else if (fEqual(statusCode[0], 1.0) && fEqual(statusCode[1], 0.0)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else if (fEqual(statusCode[0], 1.0) && fEqual(statusCode[1], 1.0)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else if (fEqual(statusCode[0], 0.5) && fEqual(statusCode[1], 0.5)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else {
            return float4(1.0, 1.0, 1.0, 1.0);
        }
    }
    
    if (uniforms.mode == ACTUAL_FOV_MODE) {
        if (fEqual(statusCode[0], 0.0) && fEqual(statusCode[1], 0.0)) {
            float3 rgb;
            if (isBlackHoleInFront) {
                rgb = sampleYUVTexture(backYTexture, backUVTexture, transformedTexCoord);
            } else {
                rgb = sampleYUVTexture(frontYTexture, frontUVTexture, transformedTexCoord);
            }
            return float4(rgb, 1.0);
        } else if (fEqual(statusCode[0], 0.0) && fEqual(statusCode[1], 1.0)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else if (fEqual(statusCode[0], 1.0) && fEqual(statusCode[1], 0.0)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else if (fEqual(statusCode[0], 1.0) && fEqual(statusCode[1], 1.0)) {
            return float4(0.0, 0.0, 0.0, 1.0);
        } else if (fEqual(statusCode[0], 0.5) && fEqual(statusCode[1], 0.5)) {
            return float4(1.0, 1.0, 0.0, 1.0);
        } else {
            return float4(0.0, 0.0, 1.0, 1.0);
        }
    }
    
    return float4(1.0, 0.0, 1.0, 1.0);
}


/*
 
 kernel void postProcess(texture2d<float, access::read_write> lut    [[texture(0)]],
                         constant uint &sliceWidth                   [[buffer(0)]],
                         constant uint &textureWidth                 [[buffer(1)]],
                         uint2 gid [[thread_position_in_grid]]) {
     if (gid.y >= textureWidth / 2 - sliceWidth / 2 && gid.y < textureWidth / 2 + sliceWidth / 2) {
         float4 leftPixel    = lut.read(uint2(gid.x, gid.y - sliceWidth / 2));
         float4 rightPixel   = lut.read(uint2(gid.x, gid.y + sliceWidth / 2));
         
         float factor = float(gid.y - (textureWidth / 2 - sliceWidth / 2)) / sliceWidth;
         float2 interpolatedTexCoords = mix(leftPixel.xy, rightPixel.xy, factor);
         
         // We interpolate the texture coordinates, but just copy down the
         // status code
         float4 finalPixel = float4(interpolatedTexCoords, leftPixel.zw);
         
         lut.write(finalPixel, gid);
     }
 }

 */
