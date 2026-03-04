use hyper::{service::{make_service_fn, service_fn}, Body, Request, Response, Server};
use std::convert::Infallible;
use std::env;
use std::net::SocketAddr;

async fn handle(_req: Request<Body>) -> Result<Response<Body>, Infallible> {
    Ok(Response::builder()
        .status(200)
        .header("content-type", "text/plain")
        .header("connection", "close")
        .body(Body::from("Hello, World!"))
        .unwrap())
}

fn get_port() -> u16 {
    let env_port = env::var("TFB_PORT")
        .or_else(|_| env::var("PORT"))
        .unwrap_or_else(|_| "8081".into());
    env_port.parse().unwrap_or(8081)
}

fn main() {
    let addr = SocketAddr::from(([0, 0, 0, 0], get_port()));
    let make_service = make_service_fn(|_| async { Ok::<_, Infallible>(service_fn(handle)) });
    let runtime = tokio::runtime::Builder::new_current_thread()
        .enable_all()
        .build()
        .unwrap();
    runtime
        .block_on(
            Server::try_bind(&addr)
                .unwrap()
                .serve(make_service),
        )
        .unwrap();
}
