[LICENSE](LICENSE)

#  Black Hole Vision

Black Hole Vision takes live video feeds from the front and rear facing cameras of the iPhone and simulates the effects of lensing by a rotating (Kerr) black hole. The result is displayed in real-time to the user's screen.

The user interface is implemented using Swift and the SwiftUI framework. The lensing calculations are done on the GPU via Metal, Apple's shading (graphics) language.

The code was written at Vanderbilt University by Trevor Gravely with input from Dr. Roman Berens and Prof. Alex Lupsasca. We are grateful to Dominic Chang for sharing his experience with his own lensing software, available on his personal website, https://dominic-chang.com/, or his GitHub, https://github.com/dominic-chang). This project was supported by CAREER award PHY-2340457 and grant AST-2307888 from the National Science Foundation.

Metal implementations of the Jacobi elliptic functions, incomplete elliptic integrals, and complete elliptic integrals are ported from https://www.gnu.org/software/gsl/. 
