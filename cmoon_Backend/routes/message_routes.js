const express = require('express');
const { Op, literal } = require('sequelize');
const db = require('../models');

const router = express.Router();
const Message = db.Message;
const Conversation = db.Conversation;
const BlockedUser = db.BlockedUser;

// ---------------- SEND MESSAGE ----------------
router.post('/send', async (req, res) => {
  const { sender_id, receiver_id, message } = req.body;

  // 🚫 block check
  const blocked = await BlockedUser.findOne({
    where: {
      [Op.or]: [
        { blocker_id: sender_id, blocked_id: receiver_id },
        { blocker_id: receiver_id, blocked_id: sender_id },
      ],
    },
  });

  if (blocked) {
    return res.status(403).json({ message: 'User is blocked' });
  }

  let convo = await Conversation.findOne({
    where: {
      [Op.or]: [
        { user1_id: sender_id, user2_id: receiver_id },
        { user1_id: receiver_id, user2_id: sender_id },
      ],
    },
  });

  if (!convo) {
    convo = await Conversation.create({
      user1_id: sender_id,
      user2_id: receiver_id,
    });
  }

  const msg = await Message.create({
    conversation_id: convo.id,
    sender_id,
    receiver_id,
    message,
    status: 'sent',
    deleted_for: [],
  });

  res.json(msg);
});

// ---------------- LOAD CHAT (FIXED) ----------------
router.get('/:user1/:user2', async (req, res) => {
  const user1 = parseInt(req.params.user1);
  const user2 = parseInt(req.params.user2);

  const convo = await Conversation.findOne({
    where: {
      [Op.or]: [
        { user1_id: user1, user2_id: user2 },
        { user1_id: user2, user2_id: user1 },
      ],
    },
  });

  if (!convo) return res.json([]);

  const messages = await Message.findAll({
    where: {
      conversation_id: convo.id,
      [Op.and]: [
        // ✅ THIS IS THE FIX
        literal(`NOT JSON_CONTAINS(deleted_for, '${user1}')`),
      ],
    },
    order: [['createdAt', 'ASC']],
  });

  res.json(messages);
});

// ---------------- DELETE FOR ME ----------------
router.post('/delete-for-me', async (req, res) => {
  const { messageId, userId } = req.body;

  const msg = await Message.findByPk(messageId);
  if (!msg) return res.sendStatus(404);

  const deletedFor = msg.deleted_for || [];

  if (!deletedFor.includes(userId)) {
    deletedFor.push(userId);
  }

  msg.deleted_for = deletedFor;
  await msg.save();

  res.sendStatus(200);
});

// ---------------- CLEAR CHAT ----------------
router.post('/clear-chat', async (req, res) => {
  const { userId, otherUserId } = req.body;

  const convo = await Conversation.findOne({
    where: {
      [Op.or]: [
        { user1_id: userId, user2_id: otherUserId },
        { user1_id: otherUserId, user2_id: userId },
      ],
    },
  });

  if (!convo) return res.sendStatus(200);

  const messages = await Message.findAll({
    where: { conversation_id: convo.id },
  });

  for (const msg of messages) {
    const deletedFor = msg.deleted_for || [];
    if (!deletedFor.includes(userId)) {
      deletedFor.push(userId);
      msg.deleted_for = deletedFor;
      await msg.save();
    }
  }

  res.sendStatus(200);
});

// ---------------- BLOCK USER ----------------
router.post('/block', async (req, res) => {
  const { blocker_id, blocked_id } = req.body;

  const exists = await BlockedUser.findOne({
    where: { blocker_id, blocked_id },
  });

  if (!exists) {
    await BlockedUser.create({ blocker_id, blocked_id });
  }

  res.sendStatus(200);
});

// ---------------- CHECK BLOCK ----------------
router.get('/is-blocked/:me/:other', async (req, res) => {
  const { me, other } = req.params;

  const blocked = await BlockedUser.findOne({
    where: {
      [Op.or]: [
        { blocker_id: me, blocked_id: other },
        { blocker_id: other, blocked_id: me },
      ],
    },
  });

  res.json({ blocked: !!blocked });
});

module.exports = router;
