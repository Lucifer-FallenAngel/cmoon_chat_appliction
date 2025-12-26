const express = require('express');
require('dotenv').config();
const http = require('http');
const { Server } = require('socket.io');
const { connectDB } = require('./config/db');
const db = require('./models');

const app = express();
const server = http.createServer(app);

const io = new Server(server, {
  cors: { origin: '*' },
});

app.use(express.json());
app.use('/uploads', express.static('uploads'));

app.use('/api/auth', require('./routes/auth_routes'));
app.use('/api/users', require('./routes/user_routes'));
app.use('/api/messages', require('./routes/message_routes'));

// userId -> socketId
let onlineUsers = {};

io.on('connection', (socket) => {
  console.log('🟢 Socket connected:', socket.id);

  // ---------------- USER ONLINE ----------------
  socket.on('user-online', (userId) => {
    if (!userId) return;

    // Ensure only one socket per user
    onlineUsers[userId] = socket.id;

    io.emit('online-users', Object.keys(onlineUsers));
  });

  // ---------------- MESSAGE NOTIFY ----------------
  socket.on('send-message', (data) => {
    if (!data || !data.receiver_id) return;

    const receiverSocketId = onlineUsers[data.receiver_id];

    // Notify receiver only (do NOT store message here)
    if (receiverSocketId) {
      io.to(receiverSocketId).emit('receive-message', {
        conversation_id: data.conversation_id,
        sender_id: data.sender_id,
        receiver_id: data.receiver_id,
      });
    }
  });

  // ---------------- DISCONNECT ----------------
  socket.on('disconnect', () => {
    console.log('🔴 Socket disconnected:', socket.id);

    // Remove disconnected socket from onlineUsers
    for (const userId of Object.keys(onlineUsers)) {
      if (onlineUsers[userId] === socket.id) {
        delete onlineUsers[userId];
        break;
      }
    }

    io.emit('online-users', Object.keys(onlineUsers));
  });
});

const PORT = process.env.PORT || 5000;

(async () => {
  try {
    await connectDB();
    await db.sequelize.sync({ alter: true });

    server.listen(PORT, () => {
      console.log(`🚀 Server running on port ${PORT}`);
    });
  } catch (err) {
    console.error('❌ Server failed to start:', err);
  }
})();
