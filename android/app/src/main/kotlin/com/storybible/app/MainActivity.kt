package com.storybible.app

import android.annotation.TargetApi
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.view.KeyEvent
import android.view.View
import android.view.ViewGroup
import android.webkit.ClientCertRequest
import android.webkit.HttpAuthHandler
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private val webViewGuardHandler = Handler(Looper.getMainLooper())
    private var webViewGuardScansRemaining = 0

    private val webViewGuardScan = object : Runnable {
        override fun run() {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

            installWebViewRenderGuards(window.decorView)
            webViewGuardScansRemaining -= 1
            if (webViewGuardScansRemaining > 0) {
                webViewGuardHandler.postDelayed(this, WEB_VIEW_GUARD_SCAN_DELAY_MS)
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startWebViewGuardScan()
    }

    override fun onResume() {
        super.onResume()
        startWebViewGuardScan()
    }

    override fun onPause() {
        webViewGuardHandler.removeCallbacks(webViewGuardScan)
        super.onPause()
    }

    private fun startWebViewGuardScan() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        webViewGuardScansRemaining = WEB_VIEW_GUARD_SCAN_COUNT
        webViewGuardHandler.removeCallbacks(webViewGuardScan)
        webViewGuardHandler.post(webViewGuardScan)
    }

    private fun installWebViewRenderGuards(view: View) {
        if (view is WebView) {
            guardWebView(view)
            return
        }

        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                installWebViewRenderGuards(view.getChildAt(index))
            }
        }
    }

    private fun guardWebView(webView: WebView) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val currentClient = webView.webViewClient
        if (currentClient is RenderGuardWebViewClient) return

        webView.webViewClient = RenderGuardWebViewClient(currentClient)
    }

    @TargetApi(Build.VERSION_CODES.O)
    private class RenderGuardWebViewClient(
        private val delegate: WebViewClient,
    ) : WebViewClient() {
        override fun shouldOverrideUrlLoading(
            view: WebView,
            request: WebResourceRequest,
        ): Boolean {
            return delegate.shouldOverrideUrlLoading(view, request)
        }

        @Deprecated("Deprecated in Java")
        override fun shouldOverrideUrlLoading(view: WebView, url: String): Boolean {
            return delegate.shouldOverrideUrlLoading(view, url)
        }

        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            delegate.onPageStarted(view, url, favicon)
        }

        override fun onPageFinished(view: WebView, url: String) {
            delegate.onPageFinished(view, url)
        }

        override fun onLoadResource(view: WebView, url: String) {
            delegate.onLoadResource(view, url)
        }

        override fun onPageCommitVisible(view: WebView, url: String) {
            delegate.onPageCommitVisible(view, url)
        }

        override fun onReceivedHttpError(
            view: WebView,
            request: WebResourceRequest,
            errorResponse: WebResourceResponse,
        ) {
            delegate.onReceivedHttpError(view, request, errorResponse)
        }

        override fun onReceivedError(
            view: WebView,
            request: WebResourceRequest,
            error: WebResourceError,
        ) {
            delegate.onReceivedError(view, request, error)
        }

        @Deprecated("Deprecated in Java")
        override fun onReceivedError(
            view: WebView,
            errorCode: Int,
            description: String,
            failingUrl: String,
        ) {
            delegate.onReceivedError(view, errorCode, description, failingUrl)
        }

        override fun shouldInterceptRequest(
            view: WebView,
            request: WebResourceRequest,
        ): WebResourceResponse? {
            return delegate.shouldInterceptRequest(view, request)
        }

        @Deprecated("Deprecated in Java")
        override fun shouldInterceptRequest(view: WebView, url: String): WebResourceResponse? {
            return delegate.shouldInterceptRequest(view, url)
        }

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
            delegate.doUpdateVisitedHistory(view, url, isReload)
        }

        override fun onReceivedHttpAuthRequest(
            view: WebView,
            handler: HttpAuthHandler,
            host: String,
            realm: String,
        ) {
            delegate.onReceivedHttpAuthRequest(view, handler, host, realm)
        }

        override fun onReceivedClientCertRequest(view: WebView, request: ClientCertRequest) {
            delegate.onReceivedClientCertRequest(view, request)
        }

        override fun onReceivedSslError(
            view: WebView,
            handler: SslErrorHandler,
            error: SslError,
        ) {
            delegate.onReceivedSslError(view, handler, error)
        }

        override fun onReceivedLoginRequest(
            view: WebView,
            realm: String,
            account: String?,
            args: String,
        ) {
            delegate.onReceivedLoginRequest(view, realm, account, args)
        }

        override fun onFormResubmission(view: WebView, dontResend: Message, resend: Message) {
            delegate.onFormResubmission(view, dontResend, resend)
        }

        override fun onScaleChanged(view: WebView, oldScale: Float, newScale: Float) {
            delegate.onScaleChanged(view, oldScale, newScale)
        }

        override fun onUnhandledKeyEvent(view: WebView, event: KeyEvent) {
            delegate.onUnhandledKeyEvent(view, event)
        }

        override fun onRenderProcessGone(
            view: WebView,
            detail: RenderProcessGoneDetail,
        ): Boolean {
            Log.w(
                TAG,
                "Handled WebView renderer exit: didCrash=${detail.didCrash()}, " +
                    "priority=${detail.rendererPriorityAtExit()}",
            )

            try {
                delegate.onRenderProcessGone(view, detail)
            } catch (error: Throwable) {
                Log.w(TAG, "Delegate render-exit callback failed", error)
            }

            (view.parent as? ViewGroup)?.removeView(view)
            view.destroy()
            return true
        }
    }

    companion object {
        private const val TAG = "StoryBibleWebView"
        private const val WEB_VIEW_GUARD_SCAN_COUNT = 40
        private const val WEB_VIEW_GUARD_SCAN_DELAY_MS = 350L
    }
}
