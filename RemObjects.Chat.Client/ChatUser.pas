﻿namespace RemObjects.Chat.Client;

uses
  RemObjects.Chat,
  //RemObjects.Elements.Serialization,
  RemObjects.Infrastructure.Encryption;

type
  //[Codable(NamingStyle.camelCase)]
  ChatUser = public class
  public

    constructor; empty;

    constructor withFolder(aFolder: String);
    begin
      Load(aFolder);
    end;

    method Load(aFolder: not nullable String);
    begin
      OwnKeyPair := new KeyPair withFiles(Path.Combine(aFolder, "public_key.key"),
                                          Path.Combine(aFolder, "private_key.key"),
                                          KeyFormat.Bytes);
      for each f in Folder.GetFiles(aFolder).Where(f -> f.LastPathComponent.EndsWith("_public.key")) do
        fPersons.Add(new Person(ID := Guid.TryParse(f.LastPathComponent.Substring(0, length(f.LastPathComponent)-11)),
                                PublicKey := new KeyPair withFiles(f, nil, KeyFormat.Bytes)));
    end;

    method Save(aFolder: not nullable String);
    begin
      Folder.Create(aFolder);
      OwnKeyPair.SaveToFiles(Path.Combine(aFolder, "public_key.key"),
                             Path.Combine(aFolder, "private_key.key"),
                             KeyFormat.Bytes);
      for each p in Persons do
        p.PublicKey.SaveToFiles(Path.Combine(aFolder, p.ID+"_public.key"), nil, KeyFormat.Bytes);
    end;

    //

    property UserID: Guid;
    property ChatServer: ChatServer;
    property OwnKeyPair: KeyPair;

    property Chats: ImmutableList<Chat> read fChats;
    var fChats := new List<Chat>; private;
    var fChatsByID := new Dictionary<Guid,Chat>; private;

    property Persons: ImmutableList<Person>;// read fPersons;
    var fPersons := new List<Person>; private;

    method AddChat(aChat: Chat);
    begin
      fChats.Add(aChat);
      fChatsByID[aChat.ID] := aChat;
    end;

    //

    method EncodeMessage(aMessage: ChatMessage; aChat: Chat): MessagePayload;
    begin

      var lPayload := new MessagePayload;

      var lStringData := aMessage.Payload.ToJsonString(JsonFormat.Minimal);
      var lData := Encoding.UTF8.GetBytes(lStringData);

      if aChat is var lPrivateChat: PrivateChat then begin
        lPayload.EncryptedMessage := lPrivateChat.Person.PublicKey.EncryptWithPublicKey(lData);
      end
      else if aChat is var lGroupChat: GroupChat then begin
        lPayload.EncryptedMessage := lGroupChat.SharedKeyPair.EncryptWithPublicKey(lData);
      end;

      lPayload.Signature := OwnKeyPair.SignWithPrivateKey(lData);

      //Log($"-- encode --");
      //Log($"lStringData {lStringData}");
      //Log($"lData {lData.ToHexString}");
      //Log($"lEncryptedMessage {lPayload.EncryptedMessage.ToHexString}");
      //Log($"lSignature        {lPayload.Signature}");

      result := lPayload;

    end;

    method DecodeMessage(aPayload: MessagePayload): ChatMessage;
    begin
    end;

    method DecodeMessage(aPayload: MessagePayload; aChat: Chat): ChatMessage;
    begin

      result := new ChatMessage;

      if aChat is var lPrivateChat: PrivateChat then begin

        var lDecryptedMessage := OwnKeyPair.DecryptWithPrivateKey(aPayload.EncryptedMessage);
        var lString := Encoding.UTF8.GetString(lDecryptedMessage);
        result.Payload := JsonDocument.FromString(lString);

        result.Sender := lPrivateChat.Person;
        result.SignatureValid := result.Sender.PublicKey.ValidateSignatureWithPublicKey(lDecryptedMessage, aPayload.Signature);
        if not result.SignatureValid then begin
          if RefreshPublicKey(result.Sender) then
            result.SignatureValid := result.Sender.PublicKey.ValidateSignatureWithPublicKey(lDecryptedMessage, aPayload.Signature);
        end;

      end
      else if aChat is var lGroupChat: GroupChat then begin

        var lDecryptedMessage := lGroupChat.SharedKeyPair.DecryptWithPrivateKey(aPayload.EncryptedMessage);
        var lString := Encoding.UTF8.GetString(lDecryptedMessage);
        result.Payload := JsonDocument.FromString(lString);

        var lSenderID := result.SenderID;
        if assigned(lSenderID) then begin
          result.Sender := FindSender(lSenderID);
          if assigned(result.Sender:PublicKey) then begin
            result.SignatureValid := lPrivateChat.Person.PublicKey.ValidateSignatureWithPublicKey(lDecryptedMessage, aPayload.Signature);
            if not result.SignatureValid then begin
              if RefreshPublicKey(result.Sender) then
                result.SignatureValid := result.Sender.PublicKey.ValidateSignatureWithPublicKey(lDecryptedMessage, aPayload.Signature);
            end;
          end;
        end;

      end;

      //Log($"-- decode --");
      //Log($"lSignature        {aPayload.Signature.ToHexString}");
      //Log($"lEncryptedMessage {aPayload.EncryptedMessage.ToHexString}");
      //Log($"result.Payload {result.Payload}");
      //Log($"result.SignatureValid {result.SignatureValid}");

      aChat.AddMessage(result);

    end;

    //
    //
    //

    method Connect;
    begin
      var lAuthenticationCode: Guid;// := fChatServer.GetChatAuthenticationCode;

      var lAuthenticationMessage := new Byte[2+sizeOf(Guid)*2];
      lAuthenticationMessage[0] := ord('A');
      &Array.Copy(UserID.ToByteArray, 0, lAuthenticationMessage, 1, sizeOf(Guid));
      lAuthenticationMessage[1+sizeOf(Guid)] := ord('-');
      &Array.Copy(lAuthenticationCode.ToByteArray, 0, lAuthenticationMessage, 2+sizeOf(Guid), sizeOf(Guid));

      // Connect
      // SendMessage(lAuthenticationMessage)
    end;

    method FindSender(aSenderID: Guid): nullable Person;
    begin
    end;

    method RefreshPublicKey(aPerson: Person): Boolean;
    begin

    end;


  end;

//[Codable(NamingStyle.camelCase)]
  Chat = public abstract class
  public

    property ID: not nullable Guid := Guid.NewGuid;

    method AddMessage(aMessage: ChatMessage);
    begin
      fMessages.Add(aMessage);
    end;

    var fMessages := new List<ChatMessage>; private;

  end;

    //[Codable(NamingStyle.camelCase)]
  PrivateChat = public class(Chat)
  public

  property Person: Person;

    end;

    //[Codable(NamingStyle.camelCase)]
  GroupChat = public class(Chat)
  public
  property SharedKeyPair: KeyPair;
    property Persons: List<Person>;

    //[Encode(false)]
    property PersonsByID: Dictionary<Guid,Person>;
    //[Encode(false)]
    property PersonsByShortID: Dictionary<Integer,Person>;
    end;

  ChatMessage = public class
  public
  property SignatureValid: Boolean;
    property Payload: JsonDocument;

    property SenderID: Guid read Guid.TryParse(Payload["senderId"]);
    property Sender: Person;
    end;

    //[Codable(NamingStyle.camelCase)]
  Person = public class
  public
  property ID: Guid;
    property ShortID: nullable Integer;
    property Name: nullable String;
    property Handle: nullable String;
    property Status: nullable String;
    property LastSeen: nullable DateTime;
    property PublicKey: PublicKey;

    end;

  end.