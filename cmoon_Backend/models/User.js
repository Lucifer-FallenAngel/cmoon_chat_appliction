const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const User = sequelize.define(
    'User',
    {
      id: {
        type: DataTypes.INTEGER,
        autoIncrement: true,
        primaryKey: true,
      },

      name: {
        type: DataTypes.STRING(100),
        allowNull: false,
      },

      mobile: {
        type: DataTypes.STRING(20),
        allowNull: false,
        unique: true,
      },

      email: {
        type: DataTypes.STRING(150),
        allowNull: false,
        unique: true,
      },

      gender: {
        type: DataTypes.STRING(10),
        allowNull: false,
      },

      password: {
        type: DataTypes.STRING,
        allowNull: false,
      },

      profile_pic: {
        type: DataTypes.STRING,
        allowNull: true,
      },

      last_seen: {
        type: DataTypes.DATE,
        allowNull: true,
      },

      // NEW FIELD FOR ONESIGNAL PUSH NOTIFICATIONS
      onesignal_player_id: {
        type: DataTypes.STRING,
        allowNull: true,
      },
    },
    {
      tableName: 'users',
      timestamps: true,
    }
  );

  return User;
};