import Foundation
import Supabase

@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        // Initialize Supabase client
        // The SDK automatically handles session persistence via UserDefaults
        self.client = SupabaseClient(
            supabaseURL: URL(string: SupabaseConfig.supabaseURL)!,
            supabaseKey: SupabaseConfig.supabaseAnonKey
        )

        print("✅ [SupabaseService] Initialized - session persistence enabled by default")
    }
}
