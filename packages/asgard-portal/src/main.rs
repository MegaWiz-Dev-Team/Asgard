use axum::{
    extract::Request,
    http::{header, HeaderName, HeaderValue},
    middleware::{self, Next},
    response::{Html, Response},
    routing::get,
    Router,
};
use std::net::SocketAddr;

const INDEX_HTML: &str = include_str!("index.html");

/// Security response headers (defense-in-depth alongside ingress).
///
/// The launchpad is a static HTML page with no JavaScript, so `script-src 'self'`
/// drops `'unsafe-inline'` entirely. It uses an inline `<style>` block + a couple
/// of inline `style=` attributes and loads Google Fonts, so `style-src` keeps
/// `'unsafe-inline'` and allowlists fonts.googleapis.com / fonts.gstatic.com.
/// Headers are inserted only when absent so an upstream ingress can override.
async fn set_security_headers(req: Request, next: Next) -> Response {
    const CSP: &str = "default-src 'self'; \
         script-src 'self'; \
         style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; \
         font-src 'self' https://fonts.gstatic.com; \
         img-src 'self' data:; \
         connect-src 'self'; \
         frame-ancestors 'none'; \
         base-uri 'self'; \
         form-action 'self'; \
         object-src 'none'";

    let mut res = next.run(req).await;
    let h = res.headers_mut();
    let set = |h: &mut axum::http::HeaderMap, name: HeaderName, value: &'static str| {
        if !h.contains_key(&name) {
            h.insert(name, HeaderValue::from_static(value));
        }
    };
    set(h, header::CONTENT_SECURITY_POLICY, CSP);
    set(h, header::X_CONTENT_TYPE_OPTIONS, "nosniff");
    set(h, header::X_FRAME_OPTIONS, "DENY");
    set(h, header::REFERRER_POLICY, "strict-origin-when-cross-origin");
    set(
        h,
        HeaderName::from_static("permissions-policy"),
        "camera=(), microphone=(), geolocation=()",
    );
    res
}

#[tokio::main]
async fn main() {
    // Build our application with a route
    let app = Router::new()
        .route("/", get(|| async { Html(INDEX_HTML) }))
        .layer(middleware::from_fn(set_security_headers));

    // Define the port (using 30005 to avoid collision)
    let addr = SocketAddr::from(([0, 0, 0, 0], 30005));
    println!("Asgard Portal launchpad running on http://{}", addr);

    // Run the server
    axum::serve(tokio::net::TcpListener::bind(&addr).await.unwrap(), app)
        .await
        .unwrap();
}
