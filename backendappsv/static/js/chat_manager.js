// --- VINHUNI CHAT SYSTEM - MODULE: QUẢN LÝ NHÓM & BẢO MẬT ---

window.isForwarding = false;
window.selectedUsers = [];
window.currentGroupId = "";

// 1. TẢI DANH SÁCH HỘI THOẠI (GIAO DIỆN CHUẨN ZALO - SẠCH SẼ)
// Khai báo biến toàn cục để lưu "đường ống" danh sách nhóm
window.unsubLuong1 = null;
window.unsubLuong2 = null;
window.unsubLuong3 = null;

window.loadGroupList = function() {
    const list = document.getElementById('group-list');
    if (!list) return;

    let allGroups = new Map();

    const renderUI = () => {
        list.innerHTML = '';
        if (allGroups.size === 0) {
            list.innerHTML = `
                <div class="text-center py-20 animate-fade-in">
                    <div class="text-slate-300 mb-2"> <svg class="w-12 h-12 mx-auto" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path d="M17 8h2a2 2 0 012 2v6a2 2 0 01-2 2h-2v4l-4-4H9a1.994 1.994 0 01-1.414-.586m0 0L11 14h4a2 2 0 002-2V6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2v4l.586-.586z"/></svg> </div>
                    <p class="text-slate-400 text-sm italic">Chưa có hội thoại nào cho cán bộ.</p>
                </div>`;
            return;
        }

        const sorted = Array.from(allGroups.values()).sort((a, b) => 
            (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0)
        );

        sorted.forEach(group => {
            const members = group.members || [];
            const currentUid = (window.auth && window.auth.currentUser) ? window.auth.currentUser.uid : String(window.userId);
            
            const isMember = members.includes(currentUid) || members.includes(Number(currentUid));
            const isPublic = group.visibility === 'public';
            const createdBy = group.createdBy ? String(group.createdBy) : "";
            const isAdmin = createdBy === currentUid; 
            const gName = group.name || "Hội thoại";

            // 🔥 UX ZALO: Ẩn mọi nút bấm rườm rà. Cả thẻ là một nút để nhảy vào Chat
            if (isPublic || isMember) {
                list.insertAdjacentHTML('beforeend', `
                    <div onclick="${isMember ? `goToChat('${group.id}', '${gName}')` : `joinPublicGroup('${group.id}')`}" 
                         class="group-card-item flex items-center p-4 bg-white border border-slate-200 rounded-3xl shadow-sm mb-3 animate-fade-in hover:border-blue-400 transition-all cursor-pointer active:scale-[0.98]">
                        
                        <div class="w-12 h-12 ${isMember ? 'bg-gradient-to-br from-blue-500 to-blue-700 shadow-blue-200' : 'bg-slate-400'} rounded-2xl flex items-center justify-center text-white font-extrabold mr-4 shadow-md text-lg">
                            ${gName.charAt(0).toUpperCase()}
                        </div>
                        
                        <div class="flex-1 overflow-hidden">
                            <h3 class="font-bold text-slate-800 text-base truncate w-full">${gName}</h3>
                            <div class="flex items-center space-x-2 mt-1">
                                <span class="text-[9px] px-2 py-0.5 rounded-full ${isPublic ? 'bg-green-50 text-green-600' : 'bg-slate-100 text-slate-500'} font-bold uppercase tracking-wider">
                                    ${isPublic ? '🌍 Công khai' : '🔒 Nhóm kín'}
                                </span>
                                ${isAdmin ? '<span class="text-[9px] bg-blue-50 text-blue-600 px-2 py-0.5 rounded-full font-bold uppercase tracking-wider">⭐ Admin</span>' : ''}
                            </div>
                        </div>
                        
                        ${!isMember ? `
                            <div class="pl-2">
                                <button class="bg-blue-600 text-white px-4 py-2 rounded-xl text-[10px] font-bold shadow-md">GIA NHẬP</button>
                            </div>
                        ` : ''}
                    </div>`);
            }
        });
    };

    const searchId = (window.auth && window.auth.currentUser) ? window.auth.currentUser.uid : String(window.userId);
    
    // 🔥 CHỐT CHẶN: Hủy các đường ống truy vấn cũ trước khi tạo mới (Quan trọng để ko bị trùng lặp)
    if (window.unsubLuong1) window.unsubLuong1();
    if (window.unsubLuong2) window.unsubLuong2();
    if (window.unsubLuong3) window.unsubLuong3();

    // 🔥 ÉP XUNG TỐC ĐỘ: Bổ sung limit(20) cho cả 3 luồng
    window.unsubLuong1 = window.db.collection("groups").where("members", "array-contains", searchId).limit(20)
        .onSnapshot(snap => {
            snap.forEach(doc => allGroups.set(doc.id, {id: doc.id, ...doc.data()}));
            renderUI();
        });

    if (!isNaN(searchId) && searchId !== "") {
        window.unsubLuong2 = window.db.collection("groups").where("members", "array-contains", Number(searchId)).limit(20)
            .onSnapshot(snap => {
                snap.forEach(doc => allGroups.set(doc.id, {id: doc.id, ...doc.data()}));
                renderUI();
            });
    }

    window.unsubLuong3 = window.db.collection("groups").where("visibility", "==", "public").limit(20)
        .onSnapshot(snap => {
            snap.forEach(doc => allGroups.set(doc.id, {id: doc.id, ...doc.data()}));
            renderUI();
        });
};

// 2. HÀM XÓA NHÓM (Thông minh: Xóa được cả nhóm và tin nhắn cá nhân)
window.deleteGroup = async function(groupId, groupName) {
    if (!confirm(`Bạn có chắc chắn muốn XÓA VĨNH VIỄN hội thoại "${groupName}"?\nTất cả dữ liệu sẽ bị mất!`)) return;
    
    try {
        const doc = await window.db.collection("groups").doc(groupId).get();
        if (!doc.exists) return alert("Hội thoại không tồn tại!");
        
        const data = doc.data();
        const isPrivate = data.type === "PRIVATE";
        const currentUid = (window.auth && window.auth.currentUser) ? window.auth.currentUser.uid : String(window.userId);

        if (!isPrivate && String(data.createdBy) !== currentUid) {
            return alert("🚫 Lỗi: Chỉ Chủ nhóm mới có quyền xóa nhóm này!");
        }

        await window.db.collection("groups").doc(groupId).delete();
        alert("🗑️ Đã xóa thành công!");
        
        // Thoát menu và quay về màn hình chính
        if (typeof window.toggleChatMenu === 'function') window.toggleChatMenu();
        if (typeof window.goBack === 'function') window.goBack();

    } catch (e) {
        console.error("Lỗi xóa hội thoại:", e);
        alert("Lỗi: Không thể xóa. Kiểm tra lại kết nối!");
    }
};

// 3. TẠO NHÓM MỚI
window.createNewGroup = async function() {
    const gName = document.getElementById('new-group-name').value.trim();
    const visibility = document.getElementById('new-group-visibility').value; 

    if (!gName) return alert("Sơn ơi, nhập tên nhóm đã nhé!");

    try {
        const res = await window.db.collection("groups").add({
            name: gName,
            visibility: visibility,
            members: [String(window.userId)],
            createdBy: String(window.userId), 
            type: "GROUP",
            createdAt: firebase.firestore.FieldValue.serverTimestamp()
        });
        window.closeCreateGroupModal();
        window.goToChat(res.id, gName);
    } catch (e) { alert("Lỗi tạo nhóm: Kiểm tra lại Rules!"); }
};

// 4. XEM THÀNH VIÊN
window.openMembersModal = async function(groupId, groupName) {
    const container = document.getElementById('members-list-content');
    const modal = document.getElementById('members-modal');
    if (!modal || !container) return console.error("Thiếu HTML members-modal!");

    modal.classList.remove('hidden');
    container.innerHTML = '<div class="text-center py-10 text-blue-500 animate-pulse text-[10px]">ĐANG TRUY XUẤT...</div>';

    try {
        const doc = await window.db.collection("groups").doc(groupId).get();
        if (!doc.exists) return container.innerHTML = 'Nhóm không tồn tại!';
        
        const data = doc.data();
        const members = data.members || [];
        const isAdmin = String(data.createdBy) === String(window.userId);

        const countLabel = document.getElementById('members-count');
        if (countLabel) countLabel.innerText = `${members.length} CÁN BỘ`;

        let cache = JSON.parse(localStorage.getItem('vinhuni_user_names') || '{}');
        const missingIds = members.filter(id => !cache[id.toString()]);

        if (missingIds.length > 0) {
            try {
                const res = await fetch(`/api/admin/search-user?ids=${missingIds.join(',')}`);
                const users = await res.json();
                users.forEach(u => cache[u.id] = u.name);
                localStorage.setItem('vinhuni_user_names', JSON.stringify(cache));
            } catch (err) { console.warn("Lỗi API Tên User."); }
        }

        let html = "";
        members.forEach(mId => {
            const uName = cache[mId.toString()] || `Cán bộ ${mId}`;
            html += `
                <div class="flex items-center p-3 bg-white rounded-2xl mb-2 border border-slate-100 shadow-sm animate-fade-in">
                    <div class="w-8 h-8 bg-slate-200 rounded-full flex items-center justify-center text-[10px] font-bold text-slate-500 mr-3">
                        ${uName.charAt(0).toUpperCase()}
                    </div>
                    <div class="flex-1">
                        <p class="font-bold text-slate-800 text-sm">${uName}</p>
                        <p class="text-[9px] text-slate-400 font-mono italic">${mId}</p>
                    </div>
                    ${String(mId) !== String(window.userId) && isAdmin ? `
                        <button onclick="kickMember('${groupId}', '${mId}')" class="p-2 text-red-500 hover:bg-red-50 rounded-lg">
                            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
                        </button>
                    ` : (String(mId) === String(window.userId) ? '<span class="text-[8px] font-bold text-blue-500 px-2 py-1 bg-blue-50 rounded uppercase">Tôi</span>' : '')}
                </div>`;
        });
        container.innerHTML = html;
    } catch (e) { container.innerHTML = '<p class="text-center text-red-500">Lỗi truy xuất!</p>'; }
};

// 5. THÊM THÀNH VIÊN
window.addSelectedMembers = async function() {
    if (window.selectedUsers.length === 0) return alert("Chọn cán bộ đã!");
    try {
        const groupDoc = await window.db.collection("groups").doc(window.currentGroupId).get();
        if (String(groupDoc.data().createdBy) !== String(window.userId)) return alert("🚫 Chỉ Chủ nhóm mới có quyền mời!");

        await window.db.collection("groups").doc(window.currentGroupId).update({
            members: firebase.firestore.FieldValue.arrayUnion(...window.selectedUsers)
        });
        alert(`✅ Đã thêm cán bộ!`);
        window.closeSearchModal();
    } catch (e) { alert("Lỗi phân quyền!"); }
};

// 6. GIA NHẬP NHÓM CÔNG KHAI
window.joinPublicGroup = async function(groupId) {
    if (!confirm("Tham gia nhóm này?")) return;
    try {
        await window.db.collection("groups").doc(groupId).update({
            members: firebase.firestore.FieldValue.arrayUnion(String(window.userId))
        });
    } catch (e) { alert("Lỗi gia nhập!"); }
};

// 7. TÌM KIẾM CÁN BỘ
window.handleSearch = async function(q) {
    const container = document.getElementById('search-results');
    if (q.trim().length < 2) return container.innerHTML = '';
    
    clearTimeout(window.searchTimeout);
    window.searchTimeout = setTimeout(async () => {
        try {
            const res = await fetch(`/api/admin/search-user?q=${encodeURIComponent(q)}&role=CANBO`);
            const users = await res.json();
            container.innerHTML = '';
            const canSelect = window.currentGroupId || window.isForwarding;

            users.forEach(user => {
                const isSelected = window.selectedUsers.includes(String(user.id));
                container.innerHTML += `
                    <div class="flex items-center p-3 hover:bg-slate-50 border-b border-slate-50 cursor-pointer" onclick="${canSelect ? `toggleSelectUser('${user.id}')` : `startPrivateChat('${user.id}', '${user.name}')`}">
                        <div class="flex-1">
                            <p class="font-bold text-slate-800 text-sm">${user.name}</p>
                            <p class="text-[10px] text-slate-400 uppercase tracking-widest">${user.id}</p>
                        </div>
                        ${canSelect ? `
                            <div class="w-6 h-6 border-2 rounded-full flex items-center justify-center ${isSelected ? 'bg-blue-600 border-blue-600' : 'border-slate-300'}">
                                ${isSelected ? '<svg class="w-4 h-4 text-white" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="3" d="M5 13l4 4L19 7"/></svg>' : ''}
                            </div>
                        ` : '<button class="bg-blue-50 text-blue-600 px-3 py-1 rounded-lg text-[10px] font-bold shadow-sm">NHẮN TIN</button>'}
                    </div>`;
            });
        } catch (e) { container.innerHTML = 'Lỗi API'; }
    }, 400);
};

// --- UI HELPERS CHUNG ---
window.goToChat = async function(id, name) {
    // 1. HIỆU ỨNG CHUYỂN CẢNH MƯỢT MÀ
    // Thay vì thay đổi innerHTML ngay lập tức gây "giật" mắt, ta làm mờ dần danh sách
    const list = document.getElementById('group-list');
    if (list) {
        list.style.transition = "opacity 0.25s ease-out, transform 0.25s ease-out";
        list.style.opacity = "0.3"; // Làm mờ danh sách
        list.style.transform = "scale(0.98)"; // Thu nhỏ nhẹ tạo chiều sâu
        
        // Thêm một lớp phủ Loading mỏng để người dùng biết hệ thống đang xử lý
        const overlay = document.createElement('div');
        overlay.className = "fixed inset-0 flex items-center justify-center z-[100] bg-white/20 backdrop-blur-[2px]";
        overlay.innerHTML = `<div class="w-8 h-8 border-4 border-blue-600 border-t-transparent rounded-full animate-spin"></div>`;
        document.body.appendChild(overlay);
    }

    // 🔥 BƯỚC QUAN TRỌNG: ĐỒNG BỘ HEARTBEAT TỨC THÌ
    // Báo cho Flutter cập nhật ID phòng ngay để nhịp tim không bị kẹt ở "IN_CHAT"
    if (window.FlutterChannel) {
        window.FlutterChannel.postMessage("changeRoom:" + id);
        console.log("📱 [BRIDGE] Đã báo ID phòng chat cho Flutter: " + id);
    }

    // 2. Dọn dẹp các luồng Firebase (Unsubscribe) để tránh rò rỉ bộ nhớ
    if (window.unsubLuong1) window.unsubLuong1();
    if (window.unsubLuong2) window.unsubLuong2();
    if (window.unsubLuong3) window.unsubLuong3();
    
    // 3. 🔥 ÉP FIREBASE ĐÓNG KẾT NỐI (Chốt chặn tử huyệt)
    try { 
        if (window.db) {
            await window.db.terminate(); 
            console.log("✅ Firebase Terminated.");
        }
    } catch(e) {
        console.error("❌ Firebase Terminate Error:", e);
    }

    // 4. Chuẩn bị dữ liệu Form để chuyển hướng
    const targetIdInput = document.getElementById('target-group-id');
    const targetNameInput = document.getElementById('target-group-name');
    
    if (targetIdInput) targetIdInput.value = id;
    if (targetNameInput) targetNameInput.value = name;
    
    // 5. SUBMIT FORM VỚI ĐỘ TRỄ NHỎ
    const form = document.getElementById('goto-chat-form');
    if (form) {
        const targetPathInput = form.querySelector('input[name="target_path"]');
        if (targetPathInput) {
            targetPathInput.value = "/chat-secure"; // Điều hướng vào phòng bảo mật
        }
        
        // 🔥 MẸO: Delay 50ms để trình duyệt kịp vẽ hiệu ứng mờ (Opacity) ở bước 1 
        // giúp quá trình chuyển trang cảm giác êm hơn, không bị nháy trắng
        setTimeout(() => {
            form.submit();
        }, 50);
    } else {
        // Nếu chạy trên trình duyệt Web thông thường (không qua Form)
        window.location.href = `/chat-secure?group_id=${id}&group_name=${encodeURIComponent(name)}`;
    }
};

window.goBack = async function() {
    // 1. Hiện chữ Loading
    const msgDiv = document.getElementById('chat-messages');
    if (msgDiv) msgDiv.innerHTML = '<div class="text-center py-10 text-slate-400 font-bold animate-pulse">Đang quay lại...</div>';

    // 2. Dập tắt luồng quét tin nhắn
    if (window.unsubMessages) window.unsubMessages();
    
    // 3. 🔥 CHỐT CHẶN TỬ HUYỆT: Ép Firebase nhả bộ nhớ
    try { if (window.db) await window.db.terminate(); } catch(e) {}

    // 4. Chuyển trang
    const form = document.getElementById('goto-chat-form');
    if (form) {
        document.getElementById('target-group-id').value = ""; 
        document.getElementById('target-group-name').value = "";
        window.currentGroupId = "";

        const targetPath = form.querySelector('input[name="target_path"]');
        if (targetPath) targetPath.value = "/chat-groups";

        form.submit();
    } else {
        window.location.href = '/chat-groups';
    }
};

window.showCreateGroupModal = () => { document.getElementById('create-group-modal').classList.remove('hidden'); document.getElementById('new-group-name').focus(); };
window.closeCreateGroupModal = () => document.getElementById('create-group-modal').classList.add('hidden');
window.closeSearchModal = () => document.getElementById('search-modal').classList.add('hidden');
window.closeMembersModal = () => document.getElementById('members-modal').classList.add('hidden');

window.openSearchModal = function(id, name) {
    window.currentGroupId = id; 
    window.selectedUsers = [];
    const modal = document.getElementById('search-modal');
    if (!modal) return;
    document.getElementById('modal-title').innerText = id ? "Mời cán bộ" : "Tìm cán bộ";
    const groupLabel = document.getElementById('modal-group-name');
    if (groupLabel) groupLabel.innerText = name || "";
    modal.classList.remove('hidden');
    document.getElementById('search-results').innerHTML = '';
    window.updateConfirmBar();
};

window.toggleSelectUser = function(id) {
    const sId = String(id);
    const idx = window.selectedUsers.indexOf(sId);
    if (idx > -1) window.selectedUsers.splice(idx, 1);
    else window.selectedUsers.push(sId);
    window.updateConfirmBar();
    window.handleSearch(document.getElementById('user-search-input').value);
};

window.updateConfirmBar = function() {
    const bar = document.getElementById('confirm-bar');
    if (window.currentGroupId && window.selectedUsers.length > 0) {
        bar.classList.remove('hidden');
        document.getElementById('btn-add-multi').innerText = `XÁC NHẬN THÊM (${window.selectedUsers.length})`;
    } else if (bar) bar.classList.add('hidden');
};

window.kickMember = async function(gId, mId) {
    if (!confirm("Xóa khỏi nhóm?")) return;
    try {
        await window.db.collection("groups").doc(gId).update({ members: firebase.firestore.FieldValue.arrayRemove(String(mId)) });
        window.openMembersModal(gId, "");
    } catch (e) { alert("Lỗi!"); }
};

window.startPrivateChat = async function(targetId, targetName) {
    const combinedId = [String(window.userId), String(targetId)].sort().join("_");
    const pId = `private_${combinedId}`;
    try {
        const ref = window.db.collection("groups").doc(pId);
        const doc = await ref.get();
        if (!doc.exists) {
            await ref.set({
                name: targetName,
                members: [String(window.userId), String(targetId)],
                type: "PRIVATE",
                createdAt: firebase.firestore.FieldValue.serverTimestamp()
            });
        }
        window.goToChat(pId, targetName);
    } catch (e) { alert("Lỗi!"); }
};

// ==========================================
// 🔥 MODULE MỚI: MENU CHAT TRONG PHÒNG ZALO
// ==========================================

window.toggleChatMenu = function() {
    const modal = document.getElementById('chat-menu-modal');
    if (modal) {
        if (modal.classList.contains('hidden')) {
            renderChatMenu(); 
            modal.classList.remove('hidden');
        } else {
            modal.classList.add('hidden');
        }
    } else {
        console.warn("Sơn ơi, bạn quên chèn đoạn HTML Menu vào file chat_secure.html rồi!");
    }
};
// ==========================================
// 🔥 MODULE: TÌM KIẾM (Ngoài danh sách & Trong phòng Chat)
// ==========================================

// 1. Lọc nhóm ở màn hình ngoài cùng
window.globalGroupSearch = function(query) {
    const q = query.toLowerCase().trim();
    // Lấy toàn bộ các thẻ nhóm đang hiển thị
    const items = document.querySelectorAll('.group-card-item');
    
    items.forEach(item => {
        const text = item.innerText.toLowerCase();
        // Nếu tên nhóm chứa từ khóa thì hiện, không thì ẩn đi
        if (text.includes(q)) {
            item.style.display = 'flex';
        } else {
            item.style.display = 'none';
        }
    });
};

// 2. Bật/Tắt thanh tìm kiếm trong phòng chat
window.toggleMessageSearch = function() {
    const bar = document.getElementById('msg-search-bar');
    const input = document.getElementById('inner-msg-search');
    
    if (bar) {
        if (bar.classList.contains('hidden')) {
            bar.classList.remove('hidden');
            input.focus(); // Tự động bật bàn phím
        } else {
            bar.classList.add('hidden');
            input.value = '';
            window.searchMessages(''); // Trả lại danh sách tin nhắn đầy đủ
        }
    }
};

// 3. Lọc nội dung tin nhắn (Dựa vào nội dung bóng chat)
window.searchMessages = function(query) {
    const q = query.toLowerCase().trim();
    // Giả định class CSS chứa text tin nhắn của Sơn là 'msg-bubble' (bóng chat)
    const bubbles = document.querySelectorAll('.msg-bubble'); 
    
    bubbles.forEach(bubble => {
        // Tìm thẻ bọc ngoài cùng của tin nhắn để ẩn/hiện cả cục (Avatar, Tên, Giờ)
        // Nếu Sơn dùng cấu trúc thẻ flex bọc ngoài, lệnh closest('.flex') sẽ bắt trúng
        const wrapper = bubble.closest('.flex') || bubble.parentElement;
        
        if (q === "") {
            wrapper.style.display = ''; // Hiện lại nếu xóa từ khóa
            return;
        }

        const text = bubble.innerText.toLowerCase();
        if (text.includes(q)) {
            wrapper.style.display = '';
        } else {
            wrapper.style.display = 'none'; // Ẩn tin nhắn không khớp
        }
    });
};
window.renderChatMenu = async function() {
    const container = document.getElementById('chat-menu-actions');
    if (!container) return;
    
    // Tìm ID nhóm đang hiển thị trong phòng chat
    const activeGroupId = window.groupId || document.getElementById('target-group-id')?.value;
    if (!activeGroupId) return container.innerHTML = '<div class="text-red-500 p-4">Lỗi ID nhóm</div>';

    try {
        const doc = await window.db.collection("groups").doc(activeGroupId).get();
        if (!doc.exists) return container.innerHTML = '<div class="text-red-500 p-4">Hội thoại đã xóa</div>';

        const data = doc.data();
        const currentUid = (window.auth && window.auth.currentUser) ? window.auth.currentUser.uid : String(window.userId);
        const isAdmin = String(data.createdBy) === currentUid;
        const isPrivate = data.type === "PRIVATE";
        const gName = data.name || "Hội thoại";

        let html = '';

        // Nút 1: Xem thành viên (Ai cũng thấy)
        html += `
            <button onclick="toggleChatMenu(); openMembersModal('${doc.id}', '${gName}')" class="w-full flex items-center p-4 bg-white hover:bg-blue-50 rounded-2xl transition-all shadow-sm">
                <div class="w-10 h-10 rounded-full bg-blue-100 text-blue-600 flex items-center justify-center mr-4">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"/></svg>
                </div>
                <span class="font-bold text-slate-700 text-sm">Xem thành viên nhóm</span>
            </button>
        `;

        // Nút 2: Thêm thành viên (Admin Nhóm)
        if (isAdmin && !isPrivate) {
            html += `
            <button onclick="toggleChatMenu(); openSearchModal('${doc.id}', '${gName}')" class="w-full flex items-center p-4 bg-white hover:bg-green-50 rounded-2xl transition-all shadow-sm mt-3">
                <div class="w-10 h-10 rounded-full bg-green-100 text-green-600 flex items-center justify-center mr-4">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"/></svg>
                </div>
                <span class="font-bold text-slate-700 text-sm">Thêm thành viên mới</span>
            </button>
            `;
        }

        // Nút 3: Xóa hội thoại (Admin nhóm HOẶC Chat cá nhân)
        if (isAdmin || isPrivate) {
            html += `
            <button onclick="deleteGroup('${doc.id}', '${gName}')" class="w-full flex items-center p-4 bg-white hover:bg-red-50 rounded-2xl transition-all shadow-sm mt-6 border border-red-100">
                <div class="w-10 h-10 rounded-full bg-red-100 text-red-600 flex items-center justify-center mr-4">
                    <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"/></svg>
                </div>
                <span class="font-bold text-red-600 text-sm">Xóa vĩnh viễn hội thoại</span>
            </button>
            `;
        }

        container.innerHTML = html;
    } catch(e) { container.innerHTML = '<div class="p-4 text-center text-red-500">Lỗi tải dữ liệu.</div>'; }
};