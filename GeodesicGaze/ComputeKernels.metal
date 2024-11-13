//
//  ComputeKernels.metal
//  GeodesicGaze
//
//  Created by Trevor Gravely on 9/1/24.
//

#include <metal_stdlib>
#include "MathFunctions.h"
#include "Physics.h"
#include "ComplexMath.h"

using namespace metal;

struct KerrRadialRootsResultForSwift {
    float2 r1;
    float2 r2;
    float2 r3;
    float2 r4;
    int status;
};

struct KerrLenseResultForSwift {
    float alpha;
    float beta;
    float eta;
    float lambda;
    float phif;
    float thetaf;
    int kerrLenseStatus;
};

struct ResultForSwift {
    float IrValue;
    float cosThetaObserverValue;
    float GphiValue;
    float mathcalGphisValue;
    float psiTauValue;
    float mathcalGthetasValue;
    float ellipticPValue;
    float IphiValue;
    float uplus;
    float uminus;
    float rootOfRatio;
    float deltaTheta;
    float t1;
    float t2;
    float sum;
    float sqrt1;
    float sqrt2;
    float uplusApprox;
    float epsilon;
    bool ifInput;
    int IrStatus;
    int cosThetaObserverStatus;
    int GphiStatus;
    int mathcalGphisStatus;
    int psiTauStatus;
    int mathcalGthetasStatus;
    int ellipticPStatus;
    int IphiStatus;
    int rootsResultStatus;
};

struct CosThetaResultForSwift {
    float value;
    int status;
};

struct JacobiAmResultForSwift {
    float ellipticKofmValue;
    float yShiftValue;
    float intermediateResultValue;
    int ellipticKofmStatus;
    int yShiftStatus;
    int intermediateResultStatus;
};

kernel void ellint_F_compute_kernel(const device float *angles [[buffer(0)]],
                                    const device float *moduli [[buffer(1)]],
                                    device EllintResult *results [[buffer(2)]],
                                    uint id [[thread_position_in_grid]]) {
    results[id] = ellint_F(angles[id], sqrt(moduli[id]), 1e-5, 1e-5);
}

kernel void ellint_E_compute_kernel(const device float *angles [[buffer(0)]],
                                    const device float *moduli [[buffer(1)]],
                                    device EllintResult *results [[buffer(2)]],
                                    uint id [[thread_position_in_grid]]) {
    results[id] = ellint_E(angles[id], sqrt(moduli[id]), 1e-5, 1e-5);
}

kernel void ellint_P_compute_kernel(const device float *angles [[buffer(0)]],
                                    const device float *moduli [[buffer(1)]],
                                    const device float *n [[buffer(2)]],
                                    device EllintResult *results [[buffer(3)]],
                                    uint id [[thread_position_in_grid]]) {
    results[id] = ellint_P(angles[id], sqrt(moduli[id]), -1 * n[id], 1e-5, 1e-5);
}

kernel void ellint_P_mma_compute_kernel(const device float *angles [[buffer(0)]],
                                        const device float *moduli [[buffer(1)]],
                                        const device float *n [[buffer(2)]],
                                        device EllintResult *results [[buffer(3)]],
                                        uint id [[thread_position_in_grid]]) {
    results[id] = ellint_P_mma(angles[id], moduli[id], n[id], 1e-5, 1e-5);
}

kernel void radial_roots_compute_kernel(const device float *M [[buffer(0)]],
                                        const device float *b [[buffer(1)]],
                                        device float4 *results [[buffer(2)]],
                                        uint id [[thread_position_in_grid]]) {
    results[id] = radialRoots(M[id], b[id]);
}

kernel void phiS_compute_kernel(const device float *M [[buffer(0)]],
                                const device float *ro [[buffer(1)]],
                                const device float *rs [[buffer(2)]],
                                const device float *b [[buffer(3)]],
                                device PhiSResult *results [[buffer(4)]],
                                uint id [[thread_position_in_grid]]) {
    results[id] = phiS(M[id], ro[id], rs[id], b[id]);
}

kernel void normalize_angle_compute_kernel(const device float *phi [[buffer(0)]],
                                           device float *results [[buffer(1)]],
                                           uint id [[thread_position_in_grid]]) {
    results[id] = normalizeAngle(phi[id]);
}

kernel void schwarzschild_lense_compute_kernel(const device float *M [[buffer(0)]],
                                               const device float *ro [[buffer(1)]],
                                               const device float *rs [[buffer(2)]],
                                               const device float *b [[buffer(3)]],
                                               device SchwarzschildLenseResult *results [[buffer(4)]],
                                               uint id [[thread_position_in_grid]]) {
    results[id] = schwarzschildLense(M[id], ro[id], rs[id], b[id]);
}

kernel void kerr_radial_roots_compute_kernel(const device float *a [[buffer(0)]],
                                             const device float *M [[buffer(1)]],
                                             const device float *eta [[buffer(2)]],
                                             const device float *lambda [[buffer(3)]],
                                             device KerrRadialRootsResultForSwift *results [[buffer(4)]],
                                             uint id [[thread_position_in_grid]]) {
    KerrRadialRootsResultForSwift result;
    
    KerrRadialRootsResult packedResult = kerrRadialRoots(a[id], M[id], eta[id], lambda[id]);
    
    result.r1 = packedResult.roots[0];
    result.r2 = packedResult.roots[1];
    result.r3 = packedResult.roots[2];
    result.r4 = packedResult.roots[3];
    
    result.status = packedResult.status;

    results[id] = result;
}

kernel void compute_abc_compute_kernel(const device float *a                  [[buffer(0)]],
                                             const device float *M                  [[buffer(1)]],
                                             const device float *eta                [[buffer(2)]],
                                             const device float *lambda             [[buffer(3)]],
                                             device float3 *results                 [[buffer(4)]],
                                             uint id [[thread_position_in_grid]]) {
    results[id] = computeABC(a[id], M[id], eta[id], lambda[id]);
}

kernel void compute_pq_compute_kernel(const device float *a                  [[buffer(0)]],
                                             const device float *M                  [[buffer(1)]],
                                             const device float *eta                [[buffer(2)]],
                                             const device float *lambda             [[buffer(3)]],
                                             device float2 *results                 [[buffer(4)]],
                                             uint id [[thread_position_in_grid]]) {
    results[id] = computePQ(a[id], M[id], eta[id], lambda[id]);
}

kernel void pow1over3_compute_kernel(const device float *zx [[buffer(0)]],
                                     const device float *zy [[buffer(1)]],
                                     device float2 *results [[buffer(2)]],
                                     uint id [[thread_position_in_grid]]) {
    results[id] = pow1over3(float2(zx[id], zy[id]));
}

kernel void kerr_lense_compute_kernel(const device float *dummyData [[buffer(0)]],
                                      device KerrLenseResultForSwift *results [[buffer(1)]],
                                      uint id [[thread_position_in_grid]]) {
    KerrLenseResultForSwift result;

    float2 texCoord = float2(0.4, 0.4);
    float backTextureWidth  = 1920.0;
    float backTextureHeight = 1080.0;

    float M = 1.0;
    float a = 0.1;
    float thetas = M_PI_F / 4.0;
    float rs = 1000.0;
    float ro = rs;

    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = texCoord * float2(backTextureWidth, backTextureHeight);

    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);

    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;

    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float lengthPerPixel = 0.1;
    float2 imagePlaneCoords = lengthPerPixel * relativePixelCoords;
    float alpha = imagePlaneCoords.x;
    float beta = imagePlaneCoords.y;

    result.alpha = alpha;
    result.beta = beta;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    result.eta = eta;
    result.lambda = lambda;

    // We don't currently handle the case of vortical geodesics
    if (eta <= 0.0) {
        return;
    }

    // Do the actual lensing. The result is a final theta and phi.
    KerrLenseResult kerrLenseResult = kerrLense(a, M, thetas, nuthetas, ro, rs, eta, lambda);
    result.kerrLenseStatus = kerrLenseResult.status;
    
    float phif = kerrLenseResult.phif;
    float thetaf = acos(kerrLenseResult.costhetaf);
    
    result.phif = phif;
    result.thetaf = thetaf;

    // Obtain the corresponding values of eta_flat, lambda_flat.
    FlatSpaceEtaLambdaResult flatSpaceEtaLambdaResult = flatSpaceEtaLambda(rs, thetas, 0, ro, thetaf, phif);
    if (flatSpaceEtaLambdaResult.status != SUCCESS) {
    }
    float etaflat = flatSpaceEtaLambdaResult.etaflat;
    float lambdaflat = flatSpaceEtaLambdaResult.lambdaflat;
    float pthetaSign = flatSpaceEtaLambdaResult.uthetaSign;

    // Map back to screen coordinates
    float alphaflat = -1.0 * lambdaflat / sin(thetas);
    float termUnderRadical = etaflat - lambdaflat * lambdaflat * (1.0 / tan(thetas)) * (1.0 / tan(thetas));
    if (termUnderRadical < 0.0) {
    }
    float betaflat = pthetaSign * sqrt(termUnderRadical);

    // Unwind through the texture -> screen coordinate mappings
    float2 transformedImagePlaneCoords = float2(alphaflat, betaflat);
    float2 transformedRelativePixelCoords = transformedImagePlaneCoords / lengthPerPixel;
    float2 transformedPixelCoords = transformedRelativePixelCoords + center;
    float2 transformedTexCoord = transformedPixelCoords / float2(backTextureWidth, backTextureHeight);

    // Ensure that the texture coordinate is inbounds
    if (transformedTexCoord.x < 0.0 || 1.0 < transformedTexCoord.x ||
        transformedTexCoord.y < 0.0 || 1.0 < transformedTexCoord.y) {
    }

    results[id] = result;
}

float forced_sum(float a, float b) {
    return a + b;
}

float2 pixelToScreenP(float2 pixelCoords) {
    float base = 0.04;
    float rcrit = 300.0;
    float alpha = 1000.0;
    int n = 1;
    
    float r = sqrt(pixelCoords.x * pixelCoords.x + pixelCoords.y * pixelCoords.y);
    
    if (r < rcrit) {
        return base * pixelCoords;
    }
    
    return ((1.0 / alpha) * pow(r - rcrit, n) + base) * pixelCoords;
}

struct LenseTextureCoordinateResultP {
    float2 coord;
    int status;
};

float3 rotateSphericalCoordinateP(float3 vsSpherical, float3 voSpherical) {
    float3 vsCartesian = sphericalToCartesian(vsSpherical);
    float3 voCartesian = sphericalToCartesian(voSpherical);
    
    float3 zhat = float3(0.0, 0.0, 1.0);

    float3 n1 = vsCartesian / length(vsCartesian);
    
    float3 v2 = zhat - dot(zhat, n1) * n1;
    float3 n2;
    if (fEqual(length(v2), 0.0)) {
        // When polar observer, n2 = 0 -> degenerate, arbitrary
        // up direction, just pick one in the plane.
        n2 = float3(0.0, 1.0, 0.0);
    } else {
        n2 = v2 / length(v2);
    }
    
    float3 n3 = cross(n2, n1);
    
    // This is just matrix multiplication by the matrix
    // whose rows are {n1, n3, n2}.
    float3 voHatCartesian = float3(dot(n1, voCartesian),
                                   dot(n3, voCartesian),
                                   dot(n2, voCartesian));
    
    return cartesianToSpherical(voHatCartesian);
}

LenseTextureCoordinateResultP kerrLenseTextureCoordinateP(float2 inCoord, int mode) {
    LenseTextureCoordinateResultP result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;

    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float M = 1.0;
    float a = 0.1;
    float thetas = M_PI_F / 2.0;
    float rs = 1000.0;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float2 imagePlaneCoords = pixelToScreenP(relativePixelCoords);
    float alpha = imagePlaneCoords.y;
    float beta = imagePlaneCoords.x;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    // We don't currently handle the case of vortical geodesics
    if (eta <= 0.0) {
        result.status = -50;
        return result;
    }
    
    // Do the actual lensing. The result is a final theta and phi.
    KerrLenseResult kerrLenseResult = kerrLense(a, M, thetas, nuthetas, ro, rs, eta, lambda);
    if (kerrLenseResult.status != SUCCESS) {
        result.status = -100;
        return result;
    }
    float phif = kerrLenseResult.phif;
    float thetaf = acos(kerrLenseResult.costhetaf);
    
    float3 rotatedSphericalCoordinates = rotateSphericalCoordinateP(float3(rs, thetas, 0.0),
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
        result.status = 5;
    } else if (threeFourBdd <= phifNormalized && phifNormalized <= 2.0 * M_PI_F) { // quadrant IV
        u = 0.5 * ((phifNormalized - threeFourBdd) / (2.0 * M_PI_F - threeFourBdd));
        result.status = 5;
    } else { // II or III
        u = (phifNormalized - oneTwoBdd) / (threeFourBdd - oneTwoBdd);
        result.status = 5;
    }
    float2 transformedTexCoord = float2(u, v);
    
    result.coord = transformedTexCoord;
    return result;
}

kernel void crasher_compute_kernel(const device float *dummyData [[buffer(0)]],
                                   device ResultForSwift *results [[buffer(1)]],
                                   uint id [[thread_position_in_grid]]) {
    ResultForSwift result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    float col = 9.0;
    float row = 541.0;
    
    float2 inCoord = float2(col / backTextureWidth, row / backTextureHeight);
    
    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float M = 1.0;
    float a = 0.9;
    float thetas = M_PI_F / 2.0;
    float rs = 1000.0;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float2 imagePlaneCoords = pixelToScreenP(relativePixelCoords);
    float alpha = imagePlaneCoords.y;
    float beta = imagePlaneCoords.x;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    if (eta <= 0.0) { }
    
    /*
    KerrLenseResult kerrLenseResult = kerrLense(a, M, thetas, nuthetas, ro, rs, eta, lambda);
    float phif = kerrLenseResult.phif;
    float thetaf = acos(kerrLenseResult.costhetaf);
    
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
    } else if (threeFourBdd <= phifNormalized && phifNormalized <= 2.0 * M_PI_F) { // quadrant IV
        u = 0.5 * ((phifNormalized - threeFourBdd) / (2.0 * M_PI_F - threeFourBdd));
    } else { // II or III
        u = (phifNormalized - oneTwoBdd) / (threeFourBdd - oneTwoBdd);
    }
    result.IrValue = u;
    result.IphiValue = v;
    */
    
    
    KerrRadialRootsResult rootsResult = kerrRadialRoots(a, M, eta, lambda);
    result.rootsResultStatus = rootsResult.status;
     
    float2 roots[4];
    roots[0] = rootsResult.roots[0];
    roots[1] = rootsResult.roots[1];
    roots[2] = rootsResult.roots[2];
    roots[3] = rootsResult.roots[3];
     
    if (!(isReal(roots[0]) &&
          isReal(roots[1]) &&
          isReal(roots[2]) &&
          isReal(roots[3]))) {
        result.IphiStatus = -1000;
        result.ifInput = true;
     } else {
         result.ifInput = false;
     }

    float r1 = roots[0].x;
    float r2 = roots[1].x;
    float r3 = roots[2].x;
    float r4 = roots[3].x;
    

    float rplus = M + sqrt(M * M - a * a);
    if (r4 < rplus) {
        result.IphiStatus = -100;
    }
    
    IrResult IrResult = computeIr(a, M, ro, rs, r1, r2, r3, r4);
    float Ir = IrResult.val;
    float tau = Ir;
    result.IrValue = Ir;
    result.IrStatus = IrResult.status;

    CosThetaObserverResult cosThetaObserverResult = cosThetaObserver(nuthetas, tau, a, M, thetas, eta, lambda);
    float cosThetaObserver = cosThetaObserverResult.val;
    result.cosThetaObserverValue = cosThetaObserver;
    result.cosThetaObserverStatus = cosThetaObserverResult.status;
    

    Result GphiResult = computeGphi(nuthetas, tau, a, M, thetas, eta, lambda);
    float Gphi = GphiResult.val;
    result.GphiValue = Gphi;
    result.GphiStatus = GphiResult.status;
    
    Result IphiResult = computeIphi(a, M, eta, lambda, ro, rs, r1, r2, r3, r4);
    float Iphi = IphiResult.val;
    result.IphiValue = IphiResult.val;
    result.IphiStatus = IphiResult.status;
    
    
    
    result.IrValue = -1;
    result.IphiValue = -1;
    result.GphiValue = -1;
    
    result.t1 = -1;
    result.t2 = -1;

    float deltaTheta = (1.0 / 2.0) * (1.0 - (eta + lambda * lambda) / (a * a));
    
    float alphap = eta / (a * a);
    float epsilon = alphap / (deltaTheta * deltaTheta);
    
    float uplus, uminus;
    if (epsilon < 0.01) {
        // float linearOrder       = (sqrt(deltaTheta * deltaTheta) / 2.0) * epsilon;
        // float quadraticOrder    = (1.0 / 8.0) * (sqrt(deltaTheta * deltaTheta)) * epsilon * epsilon;
        
        float linearOrder, quadraticOrder, thirdOrder;
        if (deltaTheta < 0.0) {
            // Convention is that we take the signfull term of the uplus expansion
            linearOrder    = (-1.0 * deltaTheta / 2.0) * epsilon;
            quadraticOrder = (deltaTheta / 8.0) * epsilon * epsilon;
            thirdOrder     = (-1.0 * deltaTheta / 16.0) * epsilon * epsilon * epsilon;
            
            uplus  = linearOrder + quadraticOrder + thirdOrder;
            uminus = 2.0 * deltaTheta - linearOrder - quadraticOrder - thirdOrder;
        } else {
            linearOrder    = (deltaTheta / 2.0) * epsilon;
            quadraticOrder = -1.0 * (deltaTheta / 8.0) * epsilon * epsilon;
            thirdOrder     = (deltaTheta / 16.0) * epsilon * epsilon * epsilon;

            uplus  = 2.0 * deltaTheta + linearOrder + quadraticOrder + thirdOrder;
            uminus = -1.0 * linearOrder - quadraticOrder - thirdOrder;
        }
        
        result.IrValue = linearOrder;
        result.IphiValue = quadraticOrder;
        result.GphiValue = thirdOrder;
        
        result.t1 = uplus;
        result.t2 = deltaTheta;
    } else {
        uplus = deltaTheta + sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
        uminus = deltaTheta - sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
    }
    
    
    
    // START UNWINDING GPHI
    /*
    float2 uplusUminus = computeUplusUminus(a, eta, lambda);
    
    float uplus = uplusUminus.x;
    float uminus = uplusUminus.y;
    */
    /*
    Result mathcalGphiResult = mathcalGphi(a, thetas, uplus, uminus);
    float mathcalGphis = mathcalGphiResult.val;
    result.mathcalGphisValue = mathcalGphis;
    result.mathcalGphisStatus = mathcalGphiResult.status;
    
    Result psiTauResult = Psitau(a, uplus, uminus, tau, thetas, nuthetas);
    float psiTau = psiTauResult.val;
    result.psiTauValue = psiTau;
    result.psiTauStatus = psiTauResult.status;
    
    EllintResult ellipticPResult = ellint_P_mma(psiTau, uplus / uminus, uplus, 1e-5, 1e-5);
    result.ellipticPValue = ellipticPResult.val;
    result.ellipticPStatus = ellipticPResult.status;
    
    result.t1 = uplus;
    result.t2 = uplus / uminus;
    */
    // START UNWINDING GPHI
    
    // result.t1 = Iphi + lambda * Gphi;

    results[id] = result;
}

kernel void other_crasher_compute_kernel(const device float *dummyData [[buffer(0)]],
                                   device CosThetaResultForSwift *results [[buffer(1)]],
                                   uint id [[thread_position_in_grid]]) {
    CosThetaResultForSwift result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    float2 inCoord = float2(0.0132850241, 0);
    LenseTextureCoordinateResultP lenseResult = kerrLenseTextureCoordinateP(inCoord, 0);
    
    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float M = 1.0;
    float a = 0.001;
    float thetas = M_PI_F / 2.0;
    float rs = 1000.0;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float2 imagePlaneCoords = pixelToScreenP(relativePixelCoords);
    float alpha = imagePlaneCoords.x;
    float beta = imagePlaneCoords.y;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    // We don't currently handle the case of vortical geodesics
    if (eta <= 0.0) { }
    
    KerrRadialRootsResult rootsResult = kerrRadialRoots(a, M, eta, lambda);
    
    float2 roots[4];
    roots[0] = rootsResult.roots[0];
    roots[1] = rootsResult.roots[1];
    roots[2] = rootsResult.roots[2];
    roots[3] = rootsResult.roots[3];
    
    
    // If not in case (2), then black hole emission.
    if (!(isReal(roots[0]) &&
          isReal(roots[1]) &&
          isReal(roots[2]) &&
          isReal(roots[3]))) {
    } else {
    }
    
    
    float r1 = roots[0].x;
    float r2 = roots[1].x;
    float r3 = roots[2].x;
    float r4 = roots[3].x;

    float rplus = M + sqrt(M * M - a * a);
    if (r4 < rplus) {
    }
    
    IrResult IrResult = computeIr(a, M, ro, rs, r1, r2, r3, r4);
    float Ir = IrResult.val;
    float tau = Ir;
    
    CosThetaObserverResult cosThetaObserverResult = cosThetaObserver(nuthetas, tau, a, M, thetas, eta, lambda);
    float cosThetaObserver = cosThetaObserverResult.val;
    result.value = cosThetaObserver;
    result.status = cosThetaObserverResult.status;
    
    /*
    Result GphiResult = computeGphi(nuthetas, tau, a, M, thetas, eta, lambda);
    float Gphi = GphiResult.val;
    result.GphiValue = Gphi;
    result.GphiStatus = GphiResult.status;
     */

    results[id] = result;
}

kernel void tau_compute_kernel(const device float *dummyData [[buffer(0)]],
                               device ResultForSwift *results [[buffer(1)]],
                               uint id [[thread_position_in_grid]]) {
    ResultForSwift result;
    
    float backTextureWidth = 1920.0;
    float backTextureHeight = 1080.0;
    
    float2 inCoord = float2(0.0132850241, 0);
    LenseTextureCoordinateResultP lenseResult = kerrLenseTextureCoordinateP(inCoord, 0);
    result.IrStatus = lenseResult.status;

    /*
     * The convention we use is to call the camera screen the "source" since we
     * ray trace from this location back into the geometry.
     */
    float M = 1.0;
    float a = 0.001;
    float thetas = M_PI_F / 2.0;
    float rs = 1000.0;
    float ro = rs;
    
    // Calculate the pixel coordinates of the current fragment
    float2 pixelCoords = inCoord * float2(backTextureWidth, backTextureHeight);
    
    // Calculate the pixel coordinates of the center of the image
    float2 center = float2(backTextureWidth / 2.0, backTextureHeight / 2.0);
    
    // Place the center at the origin
    float2 relativePixelCoords = pixelCoords - center;
    
    // Convert the pixel coordinates to coordinates in the image plane (alpha, beta)
    float2 imagePlaneCoords = pixelToScreenP(relativePixelCoords);
    float alpha = imagePlaneCoords.x;
    float beta = imagePlaneCoords.y;

    // Convert (alpha, beta) -> (lambda, eta)
    float lambda = -1.0 * alpha * sin(thetas);
    float eta = (alpha * alpha - a * a) * cos(thetas) * cos(thetas) + beta * beta;
    float nuthetas = sign(beta);

    // float eta = 1212.96;
    // float lambda = -208.0;

    KerrRadialRootsResult rootsResult = kerrRadialRoots(a, M, eta, lambda);
    
    float r1 = rootsResult.roots[0].x;
    float r2 = rootsResult.roots[1].x;
    float r3 = rootsResult.roots[2].x;
    float r4 = rootsResult.roots[3].x;
    
    result.rootsResultStatus = rootsResult.status;
    
    IrResult IrResult = computeIr(a, M, ro, rs, r1, r2, r3, r4);
    // result.IrStatus = IrResult.status;
    result.IrValue = IrResult.val;
    
    float tau = IrResult.val;
    
    CosThetaObserverResult cosThetaObserverResult = cosThetaObserver(thetas, tau, a, M, thetas, eta, lambda);
    result.cosThetaObserverValue = cosThetaObserverResult.val;
    result.cosThetaObserverStatus = cosThetaObserverResult.status;
    
    // START Gphi
    /*
    float deltaTheta = (1.0 / 2.0) * (1.0 - (eta + lambda * lambda) / (a * a));
    result.deltaTheta = deltaTheta;
    
    float alpha = eta / (a * a);
    float epsilon = alpha / (deltaTheta * deltaTheta);
    
    float uplus, uminus;
    if (epsilon < 0.00001) {
        float linearOrder = (sqrt(deltaTheta * deltaTheta) / 2.0) * epsilon;
        
        uplus = deltaTheta + sqrt(deltaTheta * deltaTheta) + linearOrder;
        uminus = deltaTheta - sqrt(deltaTheta * deltaTheta) - linearOrder;
        result.t1 = linearOrder;
        result.ifInput = true;
    } else {
        uplus = deltaTheta + sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
        uminus = deltaTheta - sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
        
        result.ifInput = false;
    }

    result.uplus = uplus;
    result.uminus = uminus;
    result.epsilon = epsilon;
    
    Result mathcalGphiResult = mathcalGphi(a, thetas, uplus, uminus);
    result.mathcalGphisValue = mathcalGphiResult.val;
    result.mathcalGphisStatus = mathcalGphiResult.status;
    
    MathcalGResult mathcalGthetasResult = mathcalGtheta(a, thetas, uplus, uminus);
    result.mathcalGthetasValue = mathcalGthetasResult.val;
    result.mathcalGthetasStatus = mathcalGthetasResult.status;
    float mathcalGthetas = mathcalGthetasResult.val;
    
    Result psiTauResult = Psitau(a, uplus, uminus, tau, thetas, 1);
    result.psiTauValue = psiTauResult.val;
    result.psiTauStatus = psiTauResult.status;
    float psiTau = psiTauResult.val;
    
    result.rootOfRatio = uplus / uminus;
    
    EllintResult ellipticPResult = ellint_P_mma(psiTau, uplus / uminus, uplus, 1e-5, 1e-5);
    result.ellipticPValue = ellipticPResult.val;
    result.ellipticPStatus = ellipticPResult.status;
    */
    // END Gphi
    
    // Result GphiResult = computeGphi(1, tau, a, M, thetas, eta, lambda);
    // result.GphiValue = (1.0 / sqrt(-1.0 * uminus * a * a)) * ellipticPResult.val - 1.0 * mathcalGphiResult.val;
    // result.GphiValue = GphiResult.val;
    // result.GphiStatus = GphiResult.status;
    
    /*
    float2 uplusUminus = computeUplusUminus(a, eta, lambda);
    
    float uplus = uplusUminus.x;
    float uminus = uplusUminus.y;
    */
    
    float deltaTheta = (1.0 / 2.0) * (1.0 - (eta + lambda * lambda) / (a * a));
    
    float alphap = eta / (a * a);
    float epsilon = alphap / (deltaTheta * deltaTheta);
    result.epsilon = epsilon;
    
    float uplus = 4.0;
    float uminus = 0.0;
    if (epsilon < 0.00001) {
        float linearOrder = (sqrt(deltaTheta * deltaTheta) / 2.0) * epsilon;
        
        // uplus = (deltaTheta + sqrt(deltaTheta * deltaTheta)) + linearOrder;
        if (deltaTheta < 0.0) {
            uplus = linearOrder;
            uminus = deltaTheta - sqrt(deltaTheta * deltaTheta) - linearOrder;
        } else {
            uplus = deltaTheta + sqrt(deltaTheta * deltaTheta) + linearOrder;
            uminus = -1.0 * linearOrder;
        }
    } else {
        uplus = deltaTheta + sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
        uminus = deltaTheta - sqrt(deltaTheta * deltaTheta + (eta / (a * a)));
    }

    result.uplus = uplus;
    result.uminus = uminus;
    
    Result mathcalGphiResult = mathcalGphi(a, thetas, uplus, uminus);
    float mathcalGphis = mathcalGphiResult.val;
    result.mathcalGphisValue = mathcalGphis;
    result.mathcalGphisStatus = mathcalGphiResult.status;
    
    Result psiTauResult = Psitau(a, uplus, uminus, tau, thetas, nuthetas);
    float psiTau = psiTauResult.val;
    result.psiTauValue = psiTau;
    result.psiTauStatus = psiTauResult.status;
    
    EllintResult ellipticPResult = ellint_P_mma(psiTau, uplus / uminus, uplus, 1e-5, 1e-5);
    result.ellipticPValue = ellipticPResult.val;
    result.ellipticPStatus = ellipticPResult.status;
    
    Result GphiResult = computeGphi(nuthetas, tau, a, M, thetas, eta, lambda);
    result.GphiValue = GphiResult.val;
    result.GphiStatus = GphiResult.status;
    
    Result IphiResult = computeIphi(a, M, eta, lambda, ro, rs, r1, r2, r3, r4);
    float Iphi = IphiResult.val;
    result.IphiValue = Iphi;
    result.IphiStatus = IphiResult.status;

    results[id] = result;
}
kernel void jacobiam_compute_kernel(const device float *u [[buffer(0)]],
                               const device float *m [[buffer(1)]],
                               device float *results [[buffer(2)]],
                               uint id [[thread_position_in_grid]]) {
    results[id] = jacobiam(u[id], m[id]).am;
}

kernel void jacobiam_debug_compute_kernel(const device float *uu [[buffer(0)]],
                                    device JacobiAmResultForSwift *results [[buffer(1)]],
                                    uint id [[thread_position_in_grid]]) {
    JacobiAmResultForSwift result;
    
    float u = 5.0;
    float m = 0.9;
    
    EllintResult ellintResult = ellint_Kcomp_mma(m, 1e-5, 1e-5);
    float ellipticKofm = ellintResult.val;
    float xShift = ellipticKofm;
    
    result.ellipticKofmValue = ellipticKofm;
    result.ellipticKofmStatus = ellintResult.status;
    
    ElljacResult ellipjResult = ellipj(ellipticKofm, m);
    float yShift = asin(ellipjResult.sn);
    
    result.yShiftValue = yShift;
    result.yShiftStatus = ellipjResult.status;
    
    EllamResult intermediateResult = jacobiamShifted(u + ellipticKofm, m, ellipticKofm, yShift);
    
    result.intermediateResultValue = intermediateResult.am;
    result.intermediateResultStatus = intermediateResult.status;

    results[id] = result;
}

kernel void spherical_to_cartesian_compute_kernel(const device float *r [[buffer(0)]],
                                                  const device float *theta [[buffer(1)]],
                                                  const device float *phi [[buffer(2)]],
                                                  device float3 *results [[buffer(3)]],
                                                  uint id [[thread_position_in_grid]]) {
    results[id] = sphericalToCartesian(float3(r[id], theta[id], phi[id]));
}

kernel void cartesian_to_spherical_compute_kernel(const device float *x [[buffer(0)]],
                                                  const device float *y [[buffer(1)]],
                                                  const device float *z [[buffer(2)]],
                                                  device float3 *results [[buffer(3)]],
                                                  uint id [[thread_position_in_grid]]) {
    results[id] = cartesianToSpherical(float3(x[id], y[id], z[id]));
}

kernel void rotate_spherical_coordinates_compute_kernel(const device float *vsR     [[buffer(0)]],
                                                        const device float *vsTheta [[buffer(1)]],
                                                        const device float *vsPhi   [[buffer(2)]],
                                                        const device float *voR     [[buffer(3)]],
                                                        const device float *voTheta [[buffer(4)]],
                                                        const device float *voPhi   [[buffer(5)]],
                                                        device float3 *results      [[buffer(6)]],
                                                        uint id [[thread_position_in_grid]]) {
    float3 vsSpherical = float3(vsR[id], vsTheta[id], vsPhi[id]);
    float3 voSpherical = float3(voR[id], voTheta[id], voPhi[id]);

    float3 vsCartesian = sphericalToCartesian(vsSpherical);
    float3 voCartesian = sphericalToCartesian(voSpherical);
    
    float3 zhat = float3(0.0, 0.0, 1.0);

    float3 n1 = vsCartesian / length(vsCartesian);
    
    float3 v2 = zhat - dot(zhat, n1) * n1;
    float3 n2;
    if (fEqual(length(v2), 0.0)) {
        // When polar observer, n2 = 0 -> degenerate, arbitrary
        // up direction, just pick one in the plane.
        n2 = float3(0.0, 1.0, 0.0);
    } else {
        n2 = v2 / length(v2);
    }
    
    float3 n3 = cross(n2, n1);
    
    // This is just matrix multiplication by the matrix
    // whose rows are {n1, n3, n2}.
    float3 voHatCartesian = float3(dot(n1, voCartesian),
                                   dot(n3, voCartesian),
                                   dot(n2, voCartesian));
    
    results[id] = cartesianToSpherical(voHatCartesian);
}
