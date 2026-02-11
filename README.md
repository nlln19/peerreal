# PeerReal

PeerReal is a simple [BeReal](https://bereal.com/)-like prototype developed as a seminar project.  
The app allows users to take two pictures and display them in a shared feed that is synchronized via [Ditto](https://www.ditto.com/).

## Installation & Setup

1. **Clone the Repo**

   ```bash
   git clone <REPO_URL> peerreal
   cd peerreal

2. **Get Flutter packages**

   ```bash
   flutter pub get

3. **Create and configure .env file**
- Create a file named .env in the project root (same level as pubspec.yaml).
- Add your Ditto credentials/URLs:
   ```bash
   DITTO_APP_ID=your_app_id
   DITTO_PLAYGROUND_TOKEN=your_playground_token
   DITTO_AUTH_URL=https://your-auth-server
   DITTO_WEBSOCKET_URL=wss://your-ditto-websocket

4. **Run on Web (Chrome)**

   ```bash
   flutter run -d chrome

5. **Run on Android**
- Start an Android emulator or connect a phone with [USB debugging enabled](https://web.archive.org/web/20220706143529/https://developer.android.com/training/basics/firstapp/running-app.html#RealDevice).
   ```bash
   flutter devices
   flutter run -d <ANDROID_DEVICE_ID>

## Contact

- Leandro Lika (leandro.lika@stud.unibas.ch)
- Lucca Alt (lucca.alt@stud.unibas.ch)
- Nillan Sivarasa (nillan.sivarasa@gmail.com)
