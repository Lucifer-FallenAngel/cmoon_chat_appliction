const { DataTypes } = require('sequelize');

module.exports = (sequelize) => {
  const Conversation = sequelize.define(
    'Conversation',
    {
      id: {
        type: DataTypes.INTEGER,
        autoIncrement: true,
        primaryKey: true,
      },

      user1_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },

      user2_id: {
        type: DataTypes.INTEGER,
        allowNull: false,
      },
    },
    {
      tableName: 'conversations',
      timestamps: true,
    }
  );

  return Conversation;
};