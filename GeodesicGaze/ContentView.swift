//
//  ContentView.swift
//  GeodesicGaze
//
//  Created by Trevor Gravely on 8/20/24.
//

import SwiftUI

struct ContentView: View {
    
    @State private var counter = 0
    @State private var selectedFilter = 0
    
    var body: some View {
        MultiCamView(counter: $counter, selectedFilter: $selectedFilter)
            .edgesIgnoringSafeArea(/*@START_MENU_TOKEN@*/.all/*@END_MENU_TOKEN@*/)
        //MultiCamView(counter: $counter, selectedFilter: $selectedFilter)
    }
}
