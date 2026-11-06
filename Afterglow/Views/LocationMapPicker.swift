import SwiftUI
import MapKit

/// Pick an exact coordinate for a Home or scene geofence by tapping the map.
struct LocationMapPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var selected: CLLocationCoordinate2D?

    let onSelect: (CLLocationCoordinate2D) -> Void

    init(initial: CLLocationCoordinate2D?, onSelect: @escaping (CLLocationCoordinate2D) -> Void) {
        self.onSelect = onSelect
        _selected = State(initialValue: initial)
        if let initial {
            _camera = State(initialValue: .region(MKCoordinateRegion(
                center: initial,
                span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02))))
        } else {
            _camera = State(initialValue: .userLocation(followsHeading: false, fallback: .automatic))
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $camera) {
                        UserAnnotation()
                        if let selected {
                            Annotation("Trigger location", coordinate: selected) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(size: 34))
                                    .foregroundStyle(.red)
                                    .background(.white, in: Circle())
                            }
                        }
                    }
                    .mapControls {
                        MapCompass()
                        MapUserLocationButton()
                    }
                    .onTapGesture { point in
                        if let coordinate = proxy.convert(point, from: .local) {
                            selected = coordinate
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Tap the map to place the trigger pin. You can pan and zoom first.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let selected {
                        Text(String(format: "%.5f, %.5f", selected.latitude, selected.longitude))
                            .font(.caption.monospacedDigit())
                    } else {
                        Text("No location selected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Choose location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Use Location") {
                        guard let selected else { return }
                        onSelect(selected)
                        dismiss()
                    }
                    .disabled(selected == nil)
                }
            }
        }
    }
}
