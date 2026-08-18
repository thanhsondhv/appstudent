// --- MODULE: CÁC HÀNH ĐỘNG TRÊN TIN NHẮN ---

let replyingToId = null;

// 1. Tải tin nhắn thời gian thực
// 1. Tải tin nhắn thời gian thực (Bản chuẩn 100% - Fix lỗi nút Forward)
// --- MODULE: TẢI TIN NHẮN THỜI GIAN THỰC (BẢN FULL OPTION 2026) ---

// static/js/chat_actions.js

// Khai báo biến toàn cục để lưu "đường ống" tin nhắn
window.unsubMessages = null;

// static/js/chat_actions.js

window.loadMessages = function() {
    const msgDiv = document.getElementById('chat-messages');
    if (!msgDiv) return;

    const activeGroupId = window.groupId || document.getElementById('target-group-id')?.value;
    if (!activeGroupId) return;

    if (window.unsubMessages) window.unsubMessages();

    const escapeHTML = (str) => {
        if (!str) return "";
        return str.replace(/[&<>'"]/g, t => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', "'": '&#39;', '"': '&quot;' }[t]));
    };

    // 🔥 HÀM CUỘN XUỐNG DƯỚI CÙNG CHUẨN XÁC
    const scrollToBottom = () => {
        setTimeout(() => {
            msgDiv.scrollTop = msgDiv.scrollHeight;
        }, 100);
    };

    window.unsubMessages = window.db.collection("groups").doc(activeGroupId).collection("messages")
      .orderBy("createdAt", "asc")
      .onSnapshot((snapshot) => {
          // Xóa màn hình chờ khi bắt đầu có dữ liệu
          if (msgDiv.querySelector('.animate-pulse')) msgDiv.innerHTML = '';

          snapshot.docChanges().forEach((change) => {
              const data = change.doc.data();
              const docId = change.doc.id;

              if (change.type === "added") {
                  // 🔥 THÊM TIN MỚI (CHỐNG NHÁY)
                  const html = createMessageHTML(docId, data);
                  msgDiv.insertAdjacentHTML('beforeend', html);
                  scrollToBottom();
              } 
              else if (change.type === "modified") {
                  // 🔥 CẬP NHẬT TRẠNG THÁI (ĐÃ XEM/THU HỒI/BIỂU CẢM)
                  const existingMsg = document.getElementById(`msg-wrapper-${docId}`);
                  if (existingMsg) {
                      existingMsg.outerHTML = createMessageHTML(docId, data);
                  }
              }
              
              // Tự động đánh dấu đã xem
              const seenBy = data.seenBy || [];
              const isMe = data.senderId.toString() === window.userId.toString();
              if (!isMe && !seenBy.includes(window.userId.toString())) {
                  window.db.collection("groups").doc(activeGroupId).collection("messages").doc(docId).update({
                      seenBy: firebase.firestore.FieldValue.arrayUnion(window.userId.toString())
                  });
              }
          });
      });
};

function createMessageHTML(docId, data) {
    const isMe = data.senderId.toString() === window.userId.toString();
    const isRecalled = data.isRecalled === true;
    const reactions = data.reactions || {};
    const seenBy = data.seenBy || [];
    const isSeen = seenBy.length > (isMe ? 1 : 0);
    const timeStr = data.createdAt ? new Date(data.createdAt.seconds * 1000).toLocaleTimeString([], {hour: '2-digit', minute:'2-digit'}) : '...';
    
    const rawText = data.text || "";
    const escapedText = rawText.replace(/'/g, "\\'");
    const safeSenderName = (data.senderName || "").replace(/'/g, "\\'");

    // Hiển thị tóm tắt cảm xúc
    let reactionHtml = "";
    Object.entries(reactions).forEach(([uid, emoji]) => {
        reactionHtml += `<span class="bg-white shadow-sm rounded-full px-1 text-[10px] border border-slate-100">${emoji}</span>`;
    });

    return `
        <div id="msg-wrapper-${docId}" class="flex items-end ${isMe ? 'justify-end' : 'justify-start'} mb-5 animate-fade-in relative group">
            
            ${window.isSelectionMode ? `<input type="checkbox" id="check-${docId}" onclick="selectMessage('${docId}')" class="mr-2 mb-4 w-4 h-4 accent-blue-600" ${window.selectedMessages.has(docId) ? 'checked' : ''}>` : ''}

            <div class="relative max-w-[85%]">
                <div onclick="${window.isSelectionMode ? `selectMessage('${docId}')` : `document.getElementById('action-${docId}').classList.toggle('hidden')`}" 
                     class="p-3 rounded-2xl shadow-md border border-slate-100 ${isMe ? 'bg-blue-600 text-white rounded-tr-none' : 'bg-white text-slate-800 rounded-tl-none'} ${isRecalled ? 'opacity-50 italic !bg-slate-200' : ''}">
                    
                    <p class="text-[9px] ${isMe ? 'text-blue-100' : 'text-slate-400'} font-bold mb-1 uppercase">${data.senderName}</p>

                    ${!isRecalled && data.type === 'image' ? 
                        `<img src="${data.url}" class="rounded-lg max-w-full mb-1 shadow-sm" onclick="window.open('${data.url}')">` : 
                        `<p class="text-[12px] leading-relaxed">${isRecalled ? '🚫 Tin nhắn đã bị thu hồi' : rawText.replace(/\n/g, '<br>')}</p>`
                    }
                    
                    <div class="flex items-center justify-end space-x-1 mt-1">
                        <span class="text-[8px] opacity-60">${timeStr}</span>
                        ${isMe ? `<span class="${isSeen ? 'text-blue-300' : 'text-slate-300'} text-[10px] font-bold">${isSeen ? '✔✔' : '✔'}</span>` : ''}
                    </div>
                </div>

                <div class="absolute -bottom-2 ${isMe ? 'left-0' : 'right-0'} flex space-x-0.5">${reactionHtml}</div>
            </div>

            <div id="action-${docId}" class="absolute -top-16 ${isMe ? 'right-0' : 'left-0'} hidden bg-white shadow-2xl rounded-2xl p-2 border border-slate-100 z-50 animate-fade-in min-w-[160px]">
                <div class="flex justify-around border-b pb-1 mb-2 text-lg">
                    <button onclick="addReaction('${docId}', '❤️')">❤️</button>
                    <button onclick="addReaction('${docId}', '👍')">👍</button>
                    <button onclick="addReaction('${docId}', '😂')">😂</button>
                </div>
                <div class="grid grid-cols-2 gap-1 text-[9px] font-bold text-slate-600">
                    <button onclick="copyMessage('${escapedText}')">📋 COPY</button>
                    <button onclick="toggleSelectionMode()">✅ CHỌN</button>
                    <button onclick="setReply('${docId}', '${safeSenderName}', '${escapedText}')">↩️ REPLY</button>
                    ${isMe ? `<button onclick="recallMessage('${docId}')" class="text-red-500">🗑️ THU HỒI</button>` : `<button onclick="deleteForMe('${docId}')" class="text-red-500">❌ XÓA</button>`}
                </div>
            </div>
        </div>`;
}
// static/js/chat_actions.js

async function uploadImage(input) {
    if (!input.files || !input.files[0]) return;
    
    const file = input.files[0];
    const formData = new FormData();
    formData.append("file", file);

    try {
        console.log("📤 Đang đẩy ảnh về Server VinhUni...");
        
        // 1. Gửi ảnh lên FastAPI Server
        const response = await fetch('/api/chat/upload-local', {
            method: 'POST',
            body: formData
        });
        const result = await response.json();

        if (result.url) {
            // 2. Lưu URL nội bộ vào Firebase Firestore để mọi người cùng thấy
            await window.db.collection("groups").doc(window.groupId).collection("messages").add({
                type: 'image',
                url: result.url, // URL từ server của Sơn
                text: '[Hình ảnh]',
                senderId: window.userId,
                senderName: window.userDisplayName,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                seenBy: [window.userId.toString()]
            });
            
            // 3. Bắn thông báo Push như bình thường
            if (window.targetReceiverId) {
                // Gọi hàm send-notification của Sơn
            }
        }
    } catch (e) {
        console.error("❌ Lỗi lưu trữ nội bộ:", e);
        alert("Server nội bộ không nhận được ảnh!");
    }
}
// 2. Gửi tin nhắn
async function sendMessage() {
    const input = document.getElementById('msg-input');
    const text = input.value.trim();
    if (!text) return;

    try {
        const messageData = {
            text: text,
            senderId: window.userId,
            senderName: window.userDisplayName,
            createdAt: firebase.firestore.FieldValue.serverTimestamp()
        };

        if (replyingToId) {
            const replyPreview = document.getElementById('reply-preview');
            messageData.replyToId = replyingToId;
            messageData.replyToName = replyPreview.querySelector('.font-bold').innerText.replace('Đang trả lời ', '').replace(':', '');
            messageData.replyToContent = replyPreview.querySelector('.italic').innerText;
        }

        await window.db.collection("groups").doc(window.groupId).collection("messages").add(messageData);

        input.value = ''; 
        cancelReply(); 

        if (window.targetReceiverId || window.targetIdList) {
            fetch('/api/chat/send-notification', { 
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    sender_name: window.userDisplayName,
                    receiver_id: window.targetReceiverId, 
                    id_list: window.targetIdList,         
                    message_text: text,
                    group_id: window.groupId
                })
            }).catch(err => console.error("⚠️ Lỗi đồng bộ SQL:", err));
        }
    } catch (e) { console.error("❌ Lỗi gửi tin:", e); }
}

// 3. Chức năng Chuyển tiếp (Forward)


// 3. Phản hồi tin nhắn (Reply)
function setReply(messageId, senderName, content) {
    replyingToId = messageId;
    const replyPreview = document.getElementById('reply-preview');
    if (replyPreview) {
        replyPreview.innerHTML = `
            <div class="bg-blue-50 p-2 border-l-4 border-blue-600 text-[10px] flex justify-between items-center rounded-r-lg shadow-sm w-full">
                <div class="truncate mr-2">
                    <p class="font-bold text-blue-800">Đang trả lời ${senderName}:</p>
                    <p class="text-slate-500 italic">${content}</p>
                </div>
                <button onclick="cancelReply()" class="text-slate-400 p-1">✕</button>
            </div>`;
        replyPreview.classList.remove('hidden');
        document.getElementById('msg-input').focus();
    }
}

function cancelReply() {
    replyingToId = null;
    const preview = document.getElementById('reply-preview');
    if (preview) preview.classList.add('hidden');
}

// 4. THU HỒI: Mọi người đều thấy tin nhắn đã bị thu hồi
async function recallMessage(messageId) {
    if (!confirm("Thu hồi tin nhắn này với mọi người?")) return;
    try {
        await window.db.collection("groups").doc(window.groupId).collection("messages").doc(messageId).update({
            isRecalled: true,
            text: "🚫 Tin nhắn đã bị thu hồi",
            updatedAt: firebase.firestore.FieldValue.serverTimestamp()
        });
    } catch (e) { alert("Lỗi: Bạn không có quyền thu hồi!"); }
}

// 5. XÓA PHÍA TÔI: Chỉ mình không thấy tin này
async function deleteForMe(messageId) {
    if (!confirm("Xóa tin nhắn này ở phía bạn?")) return;
    try {
        await window.db.collection("groups").doc(window.groupId).collection("messages").doc(messageId).update({
            deletedBy: firebase.firestore.FieldValue.arrayUnion(window.userId.toString())
        });
    } catch (e) { console.error("Lỗi xóa phía tôi:", e); }
}

// 6. CHUYỂN TIẾP: Gửi nội dung sang nhóm khác
// static/js/chat_actions.js

// static/js/chat_actions.js

async function forwardTo(messageText) {
    window.isForwarding = true; // Bật cờ để hiện nút xác nhận
    window.selectedUsers = []; 
    openSearchModal('', 'Chọn người nhận chuyển tiếp');
    
    const btnConfirm = document.getElementById('btn-add-multi');
    btnConfirm.innerText = "GỬI TIN CHUYỂN TIẾP";
    btnConfirm.onclick = async () => {
        if (window.selectedUsers.length === 0) return alert("Vui lòng chọn người nhận!");
        btnConfirm.disabled = true;

        try {
            for (const targetId of window.selectedUsers) {
                const combinedId = [window.userId, targetId].sort().join("_");
                const pId = `private_${combinedId}`;
                const textToSend = `[Chuyển tiếp]: ${messageText}`;

                // A. Gửi lên Firebase
                await window.db.collection("groups").doc(pId).collection("messages").add({
                    text: textToSend,
                    senderId: window.userId,
                    senderName: window.userDisplayName,
                    createdAt: firebase.firestore.FieldValue.serverTimestamp()
                });

                // B. Gửi thông báo về SQL qua Producer 8081
                fetch('/api/chat/send-notification', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        sender_name: window.userDisplayName,
                        receiver_id: targetId,
                        id_list: targetId,
                        message_text: textToSend,
                        group_id: pId
                    })
                }).catch(e => console.error("Lỗi sync Forward:", e));
            }
            alert("🚀 Đã chuyển tiếp thành công!");
            closeSearchModal();
        } catch (e) { alert("Lỗi chuyển tiếp!"); }
        finally { btnConfirm.disabled = false; window.isForwarding = false; }
    };
}