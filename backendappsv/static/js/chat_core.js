// --- CORE: KHỞI TẠO HỆ THỐNG ---
const firebaseConfig = {
    apiKey: "AIzaSyDFsKsB4CkCB9r1Vb3XXGJPL8sFfB2Z4Wc",
    authDomain: "vinhuni-portal-student.firebaseapp.com",
    projectId: "vinhuni-portal-student",
    storageBucket: "vinhuni-portal-student.firebasestorage.app",
    messagingSenderId: "306901265797",
    appId: "1:306901265797:web:5f31d30ce77cff7d2268ec"
};

if (!firebase.apps.length) {
    firebase.initializeApp(firebaseConfig);
}
window.db = firebase.firestore();
window.auth = firebase.auth();

window.currentGroupId = ""; 
window.selectedUsers = [];
window.searchTimeout = null;

async function initApp(mode) {
    console.log("🚀 Khởi tạo App, Mode:", mode);

    // 🔥 FIX 1: ĐÃ XÓA HOÀN TOÀN 'enablePersistence()'
    // Tuyệt đối không ép Firebase khóa IndexedDB trên Mobile WebView nữa!

    if (!window.token || window.token === "None" || window.token === "") {
        console.warn("❌ Mất Token");
        if (mode === 'GROUPS' && typeof window.loadGroupList === 'function') window.loadGroupList();
        return;
    }

    // LẮNG NGHE ĐĂNG NHẬP -> GỌI LOAD TIN NHẮN
    // 2. LẮNG NGHE ĐĂNG NHẬP -> KÍCH HOẠT PING & LOAD TIN NHẮN
    window.auth.onAuthStateChanged((user) => {
        if (user) {
            console.log("👤 Đã nhận diện UID:", user.uid);
            window.currentUid = user.uid;

            // 🔥 KÍCH HOẠT NHỊP TIM BÁO CÁO TRẠNG THÁI ONLINE
            if (typeof window.startPingHeartbeat === 'function') {
                window.startPingHeartbeat();
            }

            if (mode === 'GROUPS' && typeof window.loadGroupList === 'function') {
                window.loadGroupList();
            } else if (mode === 'CHAT' && typeof window.loadMessages === 'function') {
                window.loadMessages();
            }
        }
    });
    // ĐĂNG NHẬP
    try {
        await window.auth.signInWithCustomToken(window.token);
        console.log("✅ Xác thực Firebase thành công!");
    } catch (error) {
        console.error("❌ Lỗi Custom Token:", error);
    }
}
// chat_core.js

window.pingInterval = null;

window.startPingHeartbeat = function() {
    // 1. Dọn dẹp nếu có vòng lặp cũ để tránh bị bắn ping chồng chéo
    if (window.pingInterval) {
        clearInterval(window.pingInterval);
        window.pingInterval = null;
    }

    // 🔥 FIX TỬ HUYỆT: Kiểm tra xem có phải đang chạy trong WebView của Flutter không?
    // Chúng ta nhận diện dựa trên 'FlutterChannel' mà bạn đã định nghĩa ở ChatWebViewScreen
    const isFlutterWebView = typeof window.FlutterChannel !== 'undefined';

    if (isFlutterWebView) {
        console.log("📱 [ENVIRONMENT] Running in Flutter WebView. JS Heartbeat paused to prevent double pings.");
        // Nếu ở trong App, Flutter HeartbeatService đã lo việc này mỗi 10 giây rồi
        return; 
    }

    console.log("💓 [ENVIRONMENT] Standalone Web detected. JS Heartbeat started...");

    // 2. Thiết lập vòng lặp 10 giây một lần cho bản Web ngoài
    window.pingInterval = setInterval(async () => {
        // Lấy ID người dùng từ biến window.userId bạn đã truyền
        const uid = window.userId;
        
        // Lấy ID nhóm hiện tại từ biến global hoặc từ DOM
        const activeGroupId = window.currentGroupId || document.getElementById('target-group-id')?.value || "";

        if (uid && uid !== "None" && uid !== "") {
            try {
                // Gọi API Proxy trên cổng 8080 để Server 8081 cập nhật trạng thái Online
                await fetch(`/api/user/ping?user_code=${uid}&group_id=${activeGroupId}`, {
                    method: 'POST'
                });
            } catch (e) {
                console.warn("⚠️ [WEB PING] Failed. Server 8080 might be offline.");
            }
        }
    }, 10000); // 10 giây một nhịp
};