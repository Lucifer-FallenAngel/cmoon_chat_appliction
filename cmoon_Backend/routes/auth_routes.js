const express = require('express');
const bcrypt = require('bcryptjs');
const router = express.Router();
const db = require('../models');

const User = db.User;

/**
 * SIGNUP
 */
router.post('/signup', async (req, res) => {
  try {
    const { name, mobile, email, gender, password } = req.body;

    if (!name || !mobile || !email || !gender || !password) {
      return res.status(400).json({ message: 'All fields are required' });
    }

    const existingUser = await User.findOne({ where: { mobile } });
    if (existingUser) {
      return res.status(409).json({ message: 'Mobile number already registered' });
    }

    const hashedPassword = await bcrypt.hash(password, 10);

    const newUser = await User.create({
      name,
      mobile,
      email,
      gender,
      password: hashedPassword,
    });

    res.status(201).json({
      message: 'User registered successfully',
      userId: newUser.id,
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Signup failed' });
  }
});

/**
 * LOGIN (Mobile + Password)
 */
router.post('/login', async (req, res) => {
  try {
    const { mobile, password } = req.body;

    if (!mobile || !password) {
      return res.status(400).json({ message: 'Mobile and password required' });
    }

    const user = await User.findOne({ where: { mobile } });
    if (!user) {
      return res.status(404).json({ message: 'User not found' });
    }

    const isMatch = await bcrypt.compare(password, user.password);
    if (!isMatch) {
      return res.status(401).json({ message: 'Invalid credentials' });
    }

    res.json({
      message: 'Login successful',
      user: {
        id: user.id,
        name: user.name,
        mobile: user.mobile,
        email: user.email,
        gender: user.gender,
      },
    });
  } catch (error) {
    console.error(error);
    res.status(500).json({ message: 'Login failed' });
  }
});

module.exports = router;