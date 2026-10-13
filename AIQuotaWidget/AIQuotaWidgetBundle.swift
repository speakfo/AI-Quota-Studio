//
//  AIQuotaWidgetBundle.swift
//  AIQuotaWidget
//
//  Created by Aleksey Achkasov on 17.08.2026.
//

import WidgetKit
import SwiftUI

@main
struct AIQuotaWidgetBundle: WidgetBundle {
    var body: some Widget {
        ClaudeQuotaWidget()
        AntigravityQuotaWidget()
        CodexQuotaWidget()
    }
}
