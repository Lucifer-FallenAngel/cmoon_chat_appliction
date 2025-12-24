const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const db = require('../models');

const User = db.User;
const Message = db.Message;

const router = express.Router();

// ---------------- ENSURE UPLOAD FOLDER EXISTS ----------------
const uploadDir = 'uploads/profile_pics';

if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

// ---------------- MULTER CONFIG (PROFILE PIC) ----------------
const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    cb(null, uploadDir);
  },
  filename: (req, file, cb) => {
    const uniqueName =
      Date.now() + '-' + Math.round(Math.random() * 1e9);
    cb(null, uniqueName + path.extname(file.originalname));
  },
});

const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5MB
  fileFilter: (req, file, cb) => {
    const allowed = /jpeg|jpg|png/;
    const ext = allowed.test(
      path.extname(file.originalname).toLowerCase()
    );
    const mime = allowed.test(file.mimetype);

    if (ext && mime) {
      cb(null, true);
    } else {
      cb(new Error('Only JPG, JPEG, PNG allowed'));
    }
  },
});

// ---------------- GET ALL USERS + UNREAD COUNT ----------------
router.get('/', async (req, res) => {
  const myId = parseInt(req.query.myId);

  try {
    const users = await User.findAll({
      attributes: ['id', 'name', 'profile_pic'],
      order: [['createdAt', 'DESC']],
    });

    const result = [];

    for (const user of users) {
      if (user.id === myId) continue;

      const unread = await Message.count({
        where: {
          sender_id: user.id,
          receiver_id: myId,
          status: 'sent',
        },
      });

      result.push({
        id: user.id,
        name: user.name,
        profile_pic: user.profile_pic,
        unread,
      });
    }

    res.json(result);
  } catch (err) {
    console.error(err);
    res.status(500).json({ message: 'Failed to load users' });
  }
});

// ---------------- UPLOAD PROFILE PICTURE ----------------
router.post(
  '/upload-profile-pic',
  upload.single('profile_pic'),
  async (req, res) => {
    try {
      const { userId } = req.body;

      if (!userId) {
        return res.status(400).json({ message: 'User ID is required' });
      }

      if (!req.file) {
        return res.status(400).json({ message: 'No image uploaded' });
      }

      const user = await User.findByPk(userId);

      if (!user) {
        return res.status(404).json({ message: 'User not found' });
      }

      user.profile_pic = req.file.filename;
      await user.save();

      res.json({
        message: 'Profile picture uploaded successfully',
        file: req.file.filename,
      });
    } catch (error) {
      console.error(error);
      res.status(500).json({ message: 'Upload failed' });
    }
  }
);

module.exports = router;
