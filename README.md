# 🌲 Hytale Server Dockerized

Welcome to your new Hytale adventure! This repository provides a lightweight and easy-to-use setup to run a dedicated Hytale server using **Podman** (or Docker). It is built on **Alpine Linux** with **Java 25**, ensuring your server is both fast and resource-efficient.

## ✨ Features
* **Performance First**: Uses `eclipse-temurin:25-jre-alpine` and Ahead-Of-Time (`.aot`) cache for snappy boot times.
* **Persistence**: All your worlds (`universe/`), logs, and configurations stay safe in your local folder.
* **Secure Auth**: Pre-configured for encrypted credential storage to keep your server identity safe.

## 🛠️ Prerequisites
Before you start, make sure you have the following in your project folder (these are ignored by `.gitignore` to keep the repo clean):
1.  **`Assets.zip`**: The core game assets.
2.  **`Server/` folder**: Must contain `HytaleServer.jar`, `HytaleServer.aot`, and the `Licenses/` directory.
You have to download it from https://downloader.hytale.com/hytale-downloader.zip and paste it on the same Dockerfile folder.

## 🚀 Getting Started

### 1. Launch the Server
Simply run the following command to build the image and start the container in the background:
**podman-compose up -d**
**docker compose up -d**

### 2. Authentication & Persistence
To get your server online, you need to link it to your Hytale account:
1.  **Connect to the console**: Run `podman attach hytale_server` or `docker attach hytale_server`
2.  **Login**: Type `/auth login device` and follow the instructions in your browser.
3.  **Stay Logged In**: Your `config.json` is already set to use `Encrypted` persistence. Run `/auth persistence Encrypted` in the console to save your credentials.
4.  **Detach**: Press `Ctrl + P` followed by `Ctrl + Q` to exit the console without stopping the server.

### 3. Stop the Server
You can run on the same folder of the docker-compose.yml file:
**podman-compose down**
**docker compose down**

## ⚙️ Configuration
You can tweak your server directly through these files:
* **`docker-compose.yml`**: Modify the `RAM_MAX` environment variable (currently set to `4G`).
* **`config.json`**: Change the server name (*"Hytale Server"*), max players (default 10), or game mode.
* **Network**: The server listens on **UDP port 5520**.

## 📂 Internal Structure
* **`/app`**: Contains the read-only binaries and assets inside the container.
* **`/data`**: This is where your worlds, logs, and `config.json` are stored for full persistence.

## 🤝 Contributing
Feel free to open an issue or submit a pull request if you have ideas to make this setup even better.

