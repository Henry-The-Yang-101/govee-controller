import SwiftUI
import WidgetKit

@main
struct GoveeControlsBundle: WidgetBundle {
    var body: some Widget {
        LampOnControl()
        LampOffControl()
    }
}

struct LampOnControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.henryyang.GoveeController.on") {
            ControlWidgetButton(action: SetLampPowerIntent(turnOn: true)) {
                Label("Lamp On", systemImage: "lightbulb.fill")
            }
        }
        .displayName("Lamp On")
        .description("Turn on the light selected in Govee Controller.")
    }
}

struct LampOffControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.henryyang.GoveeController.off") {
            ControlWidgetButton(action: SetLampPowerIntent(turnOn: false)) {
                Label("Lamp Off", systemImage: "lightbulb.slash")
            }
        }
        .displayName("Lamp Off")
        .description("Turn off the light selected in Govee Controller.")
    }
}
