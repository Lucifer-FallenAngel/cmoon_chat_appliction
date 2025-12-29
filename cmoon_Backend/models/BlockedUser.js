const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const BlockedUser = sequelize.define(
    'BlockedUser',
    {
      id: {
        type: DataTypes.INTEGER,
        autoIncrement: true,
        primaryKey: true,
      },

      blocker_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },

      blocked_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },
    },
    {
      tableName: 'blocked_users',
      timestamps: true,
    }
  );

  return BlockedUser;
};