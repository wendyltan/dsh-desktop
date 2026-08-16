import Foundation

/// DeepSeek 账户余额接口 (`GET /user/balance`) 的响应模型。
struct BalanceInfo: Codable {
    let isAvailable: Bool
    let balanceInfos: [BalanceEntry]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }
}

struct BalanceEntry: Codable {
    let currency: String
    let totalBalance: String
    let grantedBalance: String
    let toppedUpBalance: String

    enum CodingKeys: String, CodingKey {
        case currency
        case totalBalance = "total_balance"
        case grantedBalance = "granted_balance"
        case toppedUpBalance = "topped_up_balance"
    }

    /// 已用额度 = 赠金 + 充值 - 当前余额（近似口径）。
    var used: Double {
        let granted = Double(grantedBalance) ?? 0
        let topped = Double(toppedUpBalance) ?? 0
        let total = Double(totalBalance) ?? 0
        return max(0, granted + topped - total)
    }
}
