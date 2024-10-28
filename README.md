#  Black Hole Vision

Black Hole Vision takes live video feeds from the front and rear facing cameras of the iPhone and simulates the effects of lensing by a rotating (Kerr) black hole. The result is displayed in real-time to the user's screen.

The user interface is implemented using Swift and the SwiftUI framework. The lensing calculations are done on the GPU via Metal, Apple's shading (graphics) language.

Made in collaboration with Dominic Chang (personal: https://dominic-chang.com/ GitHub: https://github.com/dominic-chang). 

Metal implementations of the Jacobi elliptic functions, incomplete elliptic integrals, and complete elliptic integrals are ported from https://www.gnu.org/software/gsl/. 
