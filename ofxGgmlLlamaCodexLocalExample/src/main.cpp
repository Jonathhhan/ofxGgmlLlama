#include "ofMain.h"
#include "ofApp.h"

int main() {
	ofLogToConsole();
	ofSetupOpenGL(1120, 720, OF_WINDOW);
	ofRunApp(new ofApp());
}
