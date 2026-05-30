package com.personal.password_manager.autofill

/**
 * Matches an autofill request's web domain against a credential's stored URL.
 * Pure string logic — no Android dependencies, so it stays simple and testable.
 */
object DomainMatcher {
    /** Extracts a bare hostname from a URL or host string, lower-cased, no "www." */
    fun hostOf(raw: String?): String? {
        if (raw.isNullOrBlank()) return null
        var s = raw.trim()
        // Strip scheme
        val schemeIdx = s.indexOf("://")
        if (schemeIdx >= 0) s = s.substring(schemeIdx + 3)
        // Strip path / query / port
        s = s.substringBefore('/').substringBefore('?').substringBefore(':')
        s = s.lowercase().removePrefix("www.")
        return s.ifBlank { null }
    }

    /**
     * True if the credential should be offered for [requestDomain].
     * Matches on exact host or registrable-suffix overlap
     * (e.g. accounts.google.com ↔ google.com).
     */
    fun matches(credentialUrl: String?, requestDomain: String?): Boolean {
        val cred = hostOf(credentialUrl) ?: return false
        val req = hostOf(requestDomain) ?: return false
        if (cred == req) return true
        return cred.endsWith(".$req") || req.endsWith(".$cred")
    }
}
