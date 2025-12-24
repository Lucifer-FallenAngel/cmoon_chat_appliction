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

let onlineUsers = {}; // userId -> socketId

io.on('connection', (socket) => {
  console.log('🟢 Connected:', socket.id);

  socket.on('user-online', (userId) => {
    onlineUsers[userId] = socket.id;
    io.emit('online-users', Object.keys(onlineUsers));
  });

  socket.on('send-message', (data) => {
    const receiverSocket = onlineUsers[data.receiver_id];

    if (receiverSocket) {
      io.to(receiverSocket).emit('receive-message', data);
    }
  });

  socket.on('disconnect', () => {
    for (const [uid, sid] of Object.entries(onlineUsers)) {
      if (sid === socket.id) delete onlineUsers[uid];
    }
    io.emit('online-users', Object.keys(onlineUsers));
  });
});


const PORT = process.env.PORT || 5000;

(async () => {
  await connectDB();
  await db.sequelize.sync({ alter: true });
  server.listen(PORT, () =>
    console.log(`🚀 Server running on port ${PORT}`)
  );
})();
