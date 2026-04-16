use axum::{
    response::Html,
    routing::get,
    Router,
};
use std::net::SocketAddr;

const INDEX_HTML: &str = include_str!("index.html");

#[tokio::main]
async fn main() {
    // Build our application with a route
    let app = Router::new()
        .route("/", get(|| async { Html(INDEX_HTML) }));

    // Define the port (using 30005 to avoid collision)
    let addr = SocketAddr::from(([0, 0, 0, 0], 30005));
    println!("Asgard Portal launchpad running on http://{}", addr);

    // Run the server
    axum::serve(tokio::net::TcpListener::bind(&addr).await.unwrap(), app)
        .await
        .unwrap();
}
